// Dr. Nam H. Le. drnamlabs.com, bunnyquant.com
import SwiftUI

struct WatchlistView: View {
    @State private var model = WatchModel()
    @State private var showSettings = false
    @State private var showAdd = false
    @State private var path: [WatchItem] = []
    private let app = AppState.shared

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 12) {
                    if model.enough {
                        Card {
                            Label(L("Hôm nay vậy là đủ rồi, mai quay lại nhé.", "That's enough for today. Come back tomorrow."), systemImage: "moon.stars")
                                .font(.subheadline).foregroundStyle(Palette.dim)
                        }
                    }
                    if model.offline {
                        Card { Label(L("Không có kết nối mạng.", "No connection."), systemImage: "wifi.slash").font(.subheadline).foregroundStyle(Palette.dim) }
                    }
                    if model.loading {
                        ProgressView().padding(.top, 60)
                    } else {
                        ForEach(model.visible) { item in
                            NavigationLink(value: item) { Row(item: item, info: model.rows[item.id], failed: model.failed.contains(item.id)) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { Task { await model.remove(item) } } label: { Label(L("Bỏ khỏi danh sách", "Remove"), systemImage: "minus.circle") }
                                }
                        }
                    }
                    Text(L("Chỉ là phân tích, không phải khuyến nghị đầu tư.", "Analysis only. Not investment advice."))
                        .font(.caption).foregroundStyle(Palette.muted).multilineTextAlignment(.center).padding(.top, 8)
                }
                .padding(16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.bg)
            .navigationTitle("BunnyQuant")
            .navigationDestination(for: WatchItem.self) { SymbolView(item: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel(L("Cài đặt", "Settings"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel(L("Thêm mã", "Add"))
                }
            }
            .refreshable { await model.refreshRows() }
        }
        .task {
            await model.load()
            #if DEBUG   // chụp màn hình trên simulator: -debugOpen NQ=F mở thẳng màn hình mã, -debugSheet settings|add mở bảng
            let a = CommandLine.arguments
            if let i = a.firstIndex(of: "-debugOpen"), i + 1 < a.count, let it = model.items.first(where: { $0.symbol == a[i + 1] }) { path = [it] }
            if let i = a.firstIndex(of: "-debugSheet"), i + 1 < a.count { showSettings = a[i + 1] == "settings"; showAdd = a[i + 1] == "add" }
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountChanged)) { _ in
            model.reset(); Task { await model.load() }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showAdd) { AddSymbolView { sym, mkt, name in Task { await model.add(symbol: sym, market: mkt, name: name) } } }
    }
}

private struct Row: View {
    let item: WatchItem
    let info: RowInfo?
    let failed: Bool

    var body: some View {
        Card {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.headline).foregroundStyle(Palette.text)
                    Text(item.symbol).font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer()
                if let info {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(fmtPrice(info.price, market: item.market)).font(.headline.monospacedDigit()).foregroundStyle(Palette.text)
                        HStack(spacing: 6) {
                            if let c = info.change {
                                Text(fmtPct(c)).font(.footnote.monospacedDigit()).foregroundStyle(c >= 0 ? Palette.buy : Palette.sell)
                            }
                            Pill(text: info.stance.word, fg: info.stance.fg, bg: info.stance.bg)
                        }
                    }
                } else if failed {
                    Text("—").foregroundStyle(Palette.muted)
                } else {
                    ProgressView()
                }
            }
        }
    }
}

/// Chọn thêm một mã từ ba nhóm mở cho mọi người: cổ phiếu Mỹ, tiền số, hợp đồng tương lai.
struct AddSymbolView: View {
    var onPick: (String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var market = "us"
    @State private var list: [(symbol: String, name: String)] = []
    @State private var query = ""
    @State private var loading = false

    private var filtered: [(symbol: String, name: String)] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? list : list.filter { $0.symbol.lowercased().contains(q) || $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("", selection: $market) {
                    Text(L("Cổ phiếu Mỹ", "US stocks")).tag("us")
                    Text(L("Tiền số", "Crypto")).tag("crypto")
                    Text(L("Hợp đồng", "Futures")).tag("futures")
                }
                .pickerStyle(.segmented).listRowBackground(Color.clear)
                if loading { ProgressView().frame(maxWidth: .infinity) }
                ForEach(filtered, id: \.symbol) { t in
                    Button { onPick(t.symbol, market, t.name); dismiss() } label: {
                        VStack(alignment: .leading) {
                            Text(t.symbol).font(.headline).foregroundStyle(Palette.text)
                            Text(t.name).font(.caption).foregroundStyle(Palette.muted)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: L("Tìm mã", "Search"))
            .navigationTitle(L("Thêm mã", "Add symbol"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L("Xong", "Done")) { dismiss() } } }
            .task(id: market) { await loadList() }
        }
    }

    private func loadList() async {
        loading = true; defer { loading = false }
        guard let data = try? await Http.send("/tickers/\(market)") else { return }
        let arr = Http.json(data)["tickers"] as? [[String: Any]] ?? []
        list = arr.compactMap { d in (d["symbol"] as? String).map { ($0, (d["name"] as? String) ?? $0) } }
    }
}
