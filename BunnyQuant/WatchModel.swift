// Dr. Nam H. Le. drnamlabs.com, bunnyquant.com
import Foundation
import Observation

extension Notification.Name {
    static let accountChanged = Notification.Name("bq.accountChanged")   // đăng nhập / đăng xuất: nạp lại danh sách
    static let accountWiped = Notification.Name("bq.accountWiped")       // đã xóa tài khoản: đăng ký lại từ đầu
}

struct WatchItem: Identifiable, Hashable {
    var serverId: String?
    var symbol: String
    var market: String
    var name: String
    var id: String { symbol + "|" + market }
}

struct RowInfo { var price: Double; var change: Double?; var stance: Stance }

/// Danh sách mã ngắn gọn: lấy từ danh sách theo dõi trên máy chủ (đã có sẵn), mỗi hàng một lượt phân tích khung ngày,
/// giữ trên máy tới khi nến ngày đóng nên mở lại app không tốn thêm lượt.
@Observable @MainActor
final class WatchModel {
    static let defaults: [WatchItem] = [
        WatchItem(symbol: "NQ=F", market: "futures", name: "Nasdaq 100"),
        WatchItem(symbol: "ES=F", market: "futures", name: "S&P 500"),
        WatchItem(symbol: "BTC-USD", market: "crypto", name: "Bitcoin"),
        WatchItem(symbol: "ETH-USD", market: "crypto", name: "Ethereum"),
        WatchItem(symbol: "AAPL", market: "us", name: "Apple"),
        WatchItem(symbol: "NVDA", market: "us", name: "NVIDIA"),
        WatchItem(symbol: "TSLA", market: "us", name: "Tesla"),
        WatchItem(symbol: "MSFT", market: "us", name: "Microsoft"),
    ]

    var items: [WatchItem] = []
    var rows: [String: RowInfo] = [:]
    var hidden: Set<String> = []          // máy chủ không mở mã này cho tài khoản (vd. vàng): ẩn lặng lẽ
    var failed: Set<String> = []
    var enough = false                    // hết lượt hôm nay
    var loading = true
    var offline = false

    private var names: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "bq.names") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "bq.names") }
    }
    private func displayName(_ symbol: String) -> String {
        Self.defaults.first { $0.symbol == symbol }.map { L($0.name == "Gold" ? "Vàng" : $0.name, $0.name) } ?? names[symbol] ?? symbol
    }

    var visible: [WatchItem] { items.filter { !hidden.contains($0.id) } }

    func load() async {
        loading = items.isEmpty
        offline = false
        do {
            var list = try await fetchList()
            if list.isEmpty, !(await Auth.shared.hasAccount()), !UserDefaults.standard.bool(forKey: "bq.seeded") {
                for d in Self.defaults {
                    _ = try? await API.call("/api/watchlist", method: "POST", body: [
                        "ticker": d.symbol, "asset_type": d.market, "timeframes": ["1d"], "lookback": "3mo", "rsi_period": 14,
                    ])
                }
                UserDefaults.standard.set(true, forKey: "bq.seeded")
                list = try await fetchList()
            }
            items = list.isEmpty ? Self.defaults : list
        } catch let e as APIError {
            offline = (e.code == .offline || e.code == .timeout)
            if items.isEmpty { items = Self.defaults }   // vẫn dùng được khi danh sách trên máy chủ lỗi
        } catch {}
        loading = false
        await refreshRows()
    }

    private func fetchList() async throws -> [WatchItem] {
        let json = Http.json(try await API.call("/api/watchlist"))
        return ((json["watches"] as? [[String: Any]]) ?? []).compactMap { w in
            guard let sym = (w["ticker"] as? String)?.uppercased(), !sym.isEmpty else { return nil }
            let market = (w["asset_type"] as? String) ?? "us"
            return WatchItem(serverId: (w["id"] as? String) ?? (w["id"] as? NSNumber)?.stringValue, symbol: sym, market: market, name: displayName(sym))
        }
    }

    /// Nối tiếp từng mã (máy chủ phân tích mất vài giây mỗi mã), mã nào có sẵn trong bộ nhớ đệm thì hiện ngay.
    func refreshRows() async {
        enough = false
        for item in visible where rows[item.id] == nil || failed.contains(item.id) {
            if let hit = ResultCache.get([item.symbol, item.market, "1d"].joined(separator: "|")), let a = Analysis(json: hit.json) {
                rows[item.id] = RowInfo(price: a.price, change: a.changePct, stance: a.stance)
            }
        }
        for item in visible where rows[item.id] == nil {
            do {
                let a = try await Service.analysis(symbol: item.symbol, market: item.market, interval: "1d")
                rows[item.id] = RowInfo(price: a.price, change: a.changePct, stance: a.stance)
                failed.remove(item.id)
            } catch let e as APIError {
                switch e.code {
                case .quota: enough = true; return
                case .locked: hidden.insert(item.id)
                default: failed.insert(item.id)
                }
            } catch { failed.insert(item.id) }
        }
    }

    func add(symbol: String, market: String, name: String) async {
        let item = WatchItem(symbol: symbol, market: market, name: name)
        guard !items.contains(where: { $0.id == item.id }) else { return }
        names[symbol] = name
        items.append(item)
        _ = try? await API.call("/api/watchlist", method: "POST", body: [
            "ticker": symbol, "asset_type": market, "timeframes": ["1d"], "lookback": "3mo", "rsi_period": 14,
        ])
        if let fresh = try? await fetchList() { items = fresh.isEmpty ? items : fresh }
        await refreshRows()
    }

    func remove(_ item: WatchItem) async {
        items.removeAll { $0.id == item.id }
        if let sid = item.serverId { _ = try? await API.call("/api/watchlist/\(sid)", method: "DELETE") }
    }

    func reset() { items = []; rows = [:]; hidden = []; failed = []; enough = false; loading = true }
}
