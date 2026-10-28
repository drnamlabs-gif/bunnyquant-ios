// Dr. Nam H. Le. drnamlabs.com, bunnyquant.com
import CryptoKit
import DeviceCheck
import Foundation

/// Máy chủ từ chối bằng thân JSON có cấu trúc ({"detail": {"error": ...}}) hoặc một câu chữ; giữ mã để từng màn hình xử lý riêng.
struct APIError: Error {
    enum Code { case quota, locked, lookback, unauthorized, billing, offline, timeout, server }
    var code: Code
    var status = 0
    var maxDays: Int?
    var message = ""
}

enum Config {
    /// Đã gồm `/api` (nginx gắn cả backend dưới một location). Đổi bằng build setting BQ_API_BASE để chạy với máy chủ dev.
    static let base: String = (Bundle.main.object(forInfoDictionaryKey: "BQ_API_BASE") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "https://bunnyquant.com/api"
}

enum Http {
    /// Một hàm cho mọi lệnh gọi: thời hạn, thân JSON, giải mã lỗi. Trả về dữ liệu thô.
    static func send(_ path: String, method: String = "GET", body: Any? = nil, token: String? = nil,
                     headers: [String: String] = [:]) async throws -> Data {
        guard let url = URL(string: Config.base + path) else { throw APIError(code: .server, message: "bad url") }
        var req = URLRequest(url: url, timeoutInterval: 45)   // phân tích mất trung vị 2s, tệ nhất ~25s
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        let data: Data, res: URLResponse
        do { (data, res) = try await URLSession.shared.data(for: req) }
        catch let e as URLError { throw APIError(code: e.code == .timedOut ? .timeout : .offline, message: e.localizedDescription) }
        let status = (res as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) { return data }
        throw decode(status, data)
    }

    private static func decode(_ status: Int, _ data: Data) -> APIError {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let detail = json?["detail"]
        var e = APIError(code: .server, status: status)
        if let s = detail as? String { e.message = s }
        if let d = detail as? [String: Any] {
            e.message = (d["message"] as? String) ?? ""
            e.maxDays = d["max_days"] as? Int
            switch d["error"] as? String {
            case "lookback_locked": e.code = .lookback
            case "subscription_active": e.code = .billing
            case "quota_exhausted": e.code = .quota
            case "feature_locked", "market_locked": e.code = .locked
            default: break
            }
        }
        if status == 401 { e.code = .unauthorized }
        if status == 429 { e.code = .quota }
        if status == 409, e.code == .server { e.code = .billing }
        if status == 403, e.code == .server { e.code = .locked }
        return e
    }

    static func json(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

/// Mỗi lần cài một tài khoản riêng: máy chủ cấp phiên sau khi Apple xác nhận đây là app thật trên máy thật (App Attest).
/// Có thể đăng nhập thêm bằng tài khoản bunnyquant.com; đăng xuất thì quay về tài khoản của máy này.
actor Auth {
    static let shared = Auth()

    struct Tokens: Codable {
        var access: String, refresh: String, expiresAt: Double
        var email: String?
    }

    private var anon: Tokens? = Auth.load("session.anon")
    private var account: Tokens? = Auth.load("session.account")
    private var inflight: Task<Tokens, Error>?

    private static func load(_ key: String) -> Tokens? {
        Keychain.get(key).flatMap { try? JSONDecoder().decode(Tokens.self, from: $0) }
    }
    private func save(_ t: Tokens?, _ key: String) {
        Keychain.set(key, t.flatMap { try? JSONEncoder().encode($0) })
    }

    var email: String? { account?.email }

    /// AppState được giao diện đọc nên chỉ ghi trên luồng chính.
    nonisolated static func show(_ email: String?) { Task { @MainActor in AppState.shared.signedInEmail = email } }

    func accessToken() async throws -> String {
        if let t = account ?? anon, t.expiresAt - Date().timeIntervalSince1970 > 60 { return t.access }
        return try await renew().access
    }

    /// Gọi sau khi nhận 401 một lần: làm mới rồi thử lại.
    func forceRefresh() async throws -> String {
        try await renew().access
    }

    /// Gộp các lệnh gọi đồng thời vào một lần làm mới / đăng ký, tránh tạo hai tài khoản.
    private func renew() async throws -> Tokens {
        if let inflight { return try await inflight.value }
        let task = Task { try await self.doRenew() }
        inflight = task
        defer { inflight = nil }
        return try await task.value
    }

    private func doRenew() async throws -> Tokens {
        if let acc = account {
            do { return try await refreshAccount(acc) }
            catch { account = nil; save(nil, "session.account"); Auth.show(nil) }
        }
        if let a = anon {
            do { return try await refreshAnon(a) } catch let e as APIError where e.code == .offline || e.code == .timeout { throw e } catch {}
        }
        return try await register()
    }

    private func tokens(from json: [String: Any], email: String? = nil) throws -> Tokens {
        guard let a = json["access_token"] as? String, let r = json["refresh_token"] as? String else {
            throw APIError(code: .server, message: "no session")
        }
        let ttl = (json["expires_in"] as? Double) ?? 3600
        return Tokens(access: a, refresh: r, expiresAt: Date().timeIntervalSince1970 + ttl, email: email)
    }

    private func register() async throws -> Tokens {
        let challenge = Http.json(try await Http.send("/api/ios/challenge"))["challenge"] as? String ?? ""
        var body: [String: Any] = ["challenge": challenge]
        if DCAppAttestService.shared.isSupported {
            // Mỗi khóa chỉ chứng thực được một lần, nên luôn tạo khóa mới cho lần đăng ký.
            let svc = DCAppAttestService.shared
            let keyId = try await svc.generateKey()
            let hash = Data(SHA256.hash(data: Data(challenge.utf8)))
            let attestation = try await svc.attestKey(keyId, clientDataHash: hash)
            body["key_id"] = keyId
            body["attestation"] = attestation.base64EncodedString()
            Keychain.set("attest.key", Data(keyId.utf8))
        }
        let t = try tokens(from: Http.json(try await Http.send("/api/ios/register", method: "POST", body: body)))
        anon = t; save(t, "session.anon")
        return t
    }

    private func refreshAnon(_ a: Tokens) async throws -> Tokens {
        let t = try tokens(from: Http.json(try await Http.send("/api/ios/refresh", method: "POST", body: ["refresh_token": a.refresh])))
        anon = t; save(t, "session.anon")
        return t
    }

    private func refreshAccount(_ a: Tokens) async throws -> Tokens {
        let data = try await Http.send("/auth/proxy/token?grant_type=refresh_token", method: "POST",
                                       body: ["refresh_token": a.refresh])
        let t = try tokens(from: Http.json(data), email: a.email)
        account = t; save(t, "session.account")
        return t
    }

    func signIn(email: String, password: String) async throws {
        let data: Data
        do {
            data = try await Http.send("/auth/proxy/token?grant_type=password", method: "POST",
                                       body: ["email": email.trimmingCharacters(in: .whitespaces).lowercased(), "password": password])
        } catch var e as APIError where e.status == 400 || e.status == 401 {
            e.code = .unauthorized; throw e
        }
        let json = Http.json(data)
        let mail = (json["user"] as? [String: Any])?["email"] as? String
        let t = try tokens(from: json, email: mail ?? email)
        account = t; save(t, "session.account")
        Auth.show(t.email)
    }

    func signOut() {
        account = nil; save(nil, "session.account")
        Auth.show(nil)
    }

    /// Sau khi xóa tài khoản: bỏ mọi phiên, lần mở tiếp theo tự đăng ký tài khoản mới.
    func wipe() {
        account = nil; anon = nil
        ["session.account", "session.anon", "attest.key"].forEach { Keychain.set($0, nil) }
        Auth.show(nil)
    }

    func hasAccount() -> Bool { account != nil }
}

enum API {
    /// Lệnh gọi có đăng nhập. 401 thì làm mới phiên và thử lại đúng một lần.
    static func call(_ path: String, method: String = "GET", body: Any? = nil) async throws -> Data {
        let token = try await Auth.shared.accessToken()
        do { return try await Http.send(path, method: method, body: body, token: token) }
        catch let e as APIError where e.code == .unauthorized {
            let fresh = try await Auth.shared.forceRefresh()
            return try await Http.send(path, method: method, body: body, token: fresh)
        }
    }
}
