// Dr. Nam H. Le. drnamlabs.com, bunnyquant.com
import CryptoKit
import Foundation

struct Candle: Identifiable {
    let t: Double, o: Double, h: Double, l: Double, c: Double
    var id: Double { t }
}

/// Kết quả một lần phân tích, đọc phòng thủ từ JSON của máy chủ: phần bị khóa là {"error": ...}, số có thể null.
/// Thiếu gì thì thẻ đó biến mất; không bao giờ hiện "NaN".
struct Analysis {
    var symbol: String, market: String, interval: String
    var stance: Stance
    var confidence: String?
    var price: Double
    var isShort: Bool
    var entry: Double?, stop: Double?, target1: Double?, target2: Double?
    var rr: Double?
    var candles: [Candle]

    /// Biên độ trung bình của 14 nến gần nhất, tính theo % giá: "giá thường dao động bao nhiêu mỗi nến".
    var typicalMovePct: Double? {
        let w = candles.suffix(14)
        guard w.count >= 5 else { return nil }
        let m = w.compactMap { $0.c > 0 ? ($0.h - $0.l) / $0.c * 100 : nil }
        return m.isEmpty ? nil : m.reduce(0, +) / Double(m.count)
    }
    private var base: Double { entry ?? price }
    /// Lỗ nếu chạm điểm cắt lỗ, % so với điểm vào.
    var riskPct: Double? { stop.map { abs(base - $0) / base * 100 } }
    /// Lãi nếu chạm mục tiêu 1, % so với điểm vào.
    var rewardPct: Double? { target1.map { abs($0 - base) / base * 100 } }

    var changePct: Double? {
        guard candles.count >= 2, let prev = candles.dropLast().last?.c, prev > 0, let last = candles.last?.c else { return nil }
        return (last - prev) / prev * 100
    }

    init?(json: [String: Any]) {
        func num(_ v: Any?) -> Double? {
            let d = (v as? Double) ?? (v as? NSNumber)?.doubleValue ?? Double(v as? String ?? "")
            return d.flatMap { $0.isFinite ? $0 : nil }
        }
        let input = json["input"] as? [String: Any] ?? [:]
        let ctx = json["price_context"] as? [String: Any] ?? [:]
        guard let price = num(ctx["current_price"]) else { return nil }
        symbol = ((input["resolved_ticker"] as? String) ?? (input["ticker"] as? String) ?? "").uppercased()
        market = input["market"] as? String ?? "us"
        interval = input["interval"] as? String ?? ""
        let decision = json["decision"] as? [String: Any] ?? [:]
        stance = Stance(decision["action"] as? String ?? "WAIT")
        confidence = (decision["confidence"] as? [String: Any])?["label"] as? String
        self.price = price
        isShort = (ctx["trade_side"] as? String) == "short"
        entry = num((ctx["entry_zone"] as? [String: Any])?["ideal"])
        stop = num(ctx["stop_loss"])
        let tg = ctx["targets"] as? [String: Any]
        target1 = num(tg?["tp1"]); target2 = num(tg?["tp2"])
        rr = num(ctx["rr_ratio"])
        candles = ((json["candles"] as? [[String: Any]]) ?? []).compactMap { d in
            guard let t = num(d["t"]), let o = num(d["o"]), let h = num(d["h"]), let l = num(d["l"]), let c = num(d["c"]) else { return nil }
            return Candle(t: t, o: o, h: h, l: l, c: c)
        }
    }
}

/// Kết quả giữ trên máy tới khi nến đang chạy đóng: trong một nến máy chủ trả đúng các số đó và vẫn tính một lượt.
enum ResultCache {
    private struct Entry: Codable { var expiresAt: Double; var body: Data }
    private static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("results", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private static let lock = NSLock()

    private static func file(_ key: String) -> URL {
        let h = SHA256.hash(data: Data(key.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(h + ".json")
    }

    /// Thời điểm nến hiện tại đóng (epoch giây, lưới UTC; tuần neo vào thứ Hai).
    static func barClose(_ interval: String, now: Date = Date()) -> Double {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let t = now.timeIntervalSince1970
        switch interval {
        case "1h": return (t / 3600).rounded(.down) * 3600 + 3600
        case "1w", "1wk":
            let day = cal.startOfDay(for: now)
            let wd = cal.component(.weekday, from: now)            // 1 = Chủ nhật
            let toMonday = (9 - wd) % 7 == 0 ? 7 : (9 - wd) % 7
            return cal.date(byAdding: .day, value: toMonday, to: day)!.timeIntervalSince1970
        default:
            return cal.startOfDay(for: now).timeIntervalSince1970 + 86400
        }
    }

    static func get(_ key: String) -> (json: [String: Any], expiresAt: Double)? {
        lock.lock(); defer { lock.unlock() }
        guard let raw = try? Data(contentsOf: file(key)), let e = try? JSONDecoder().decode(Entry.self, from: raw) else { return nil }
        if Date().timeIntervalSince1970 >= e.expiresAt { try? FileManager.default.removeItem(at: file(key)); return nil }
        return (Http.json(e.body), e.expiresAt)
    }

    static func put(_ key: String, body: Data, interval: String) {
        lock.lock(); defer { lock.unlock() }
        let e = Entry(expiresAt: barClose(interval), body: body)
        try? JSONEncoder().encode(e).write(to: file(key), options: .atomic)
    }

    static func clear() { try? FileManager.default.removeItem(at: dir); _ = dir }
}

enum Service {
    /// Số ngày lịch sử của từng lựa chọn, để lùi về mức thấp hơn khi gói giới hạn.
    private static let lookbackDays: [(String, Int)] = [("1y", 365), ("6mo", 180), ("3mo", 90), ("1mo", 30), ("5d", 5), ("1d", 1)]
    private static let defaultLookback = ["1h": "1mo", "1d": "6mo", "1w": "1y"]

    static func analysis(symbol: String, market: String, interval: String, force: Bool = false) async throws -> Analysis {
        let key = [symbol.uppercased(), market, interval].joined(separator: "|")
        if !force, let hit = ResultCache.get(key), let a = Analysis(json: hit.json) { return a }

        func fetch(_ lookback: String) async throws -> Data {
            let q = "market=\(market)&interval=\(interval)&lookback=\(lookback)&horizon=swing&risk_profile=balanced"
            let sym = symbol.uppercased().addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
            return try await API.call("/quick-decision/\(sym)?\(q)")
        }
        let first = defaultLookback[interval] ?? "3mo"
        var body: Data
        do { body = try await fetch(first) }
        catch let e as APIError where e.code == .lookback {
            // Gói giới hạn lịch sử: chọn mức dài nhất vẫn được phép thay vì bắt người dùng đoán.
            guard let max = e.maxDays, let fallback = lookbackDays.first(where: { $0.1 <= max && $0.0 != first }) else { throw e }
            body = try await fetch(fallback.0)
        }
        guard let a = Analysis(json: Http.json(body)) else { throw APIError(code: .server, message: "unreadable result") }
        ResultCache.put(key, body: body, interval: interval)
        return a
    }
}
