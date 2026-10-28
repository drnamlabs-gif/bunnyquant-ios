// Dr. Nam H. Le. drnamlabs.com, bunnyquant.com
import SwiftUI

struct SymbolView: View {
    let item: WatchItem
    @State private var interval = "1d"
    @State private var analysis: Analysis?
    @State private var loading = true
    @State private var problem: APIError?

    private let frames: [(String, String, String)] = [("1h", "1 giờ", "1 hour"), ("1d", "Ngày", "Day"), ("1w", "Tuần", "Week")]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                Picker("", selection: $interval) {
                    ForEach(frames, id: \.0) { Text(L($0.1, $0.2)).tag($0.0) }
                }
                .pickerStyle(.segmented)

                if let a = analysis {
                    Card { CandleChart(candles: a.candles, levels: chartLevels(a)) }
                    if !chartLevels(a).isEmpty { levelsCard(a) }
                    riskCard(a)
                    readingCard(a)
                } else if loading {
                    ProgressView().padding(.top, 80)
                } else if let p = problem {
                    problemView(p)
                }

                Text(L("Chỉ là phân tích, không phải khuyến nghị đầu tư. Số liệu ước lượng từ dữ liệu lịch sử và có thể sai.",
                       "Analysis only, not investment advice. Figures are estimated from historical data and can be wrong."))
                    .font(.caption).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
            }
            .padding(16)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.bg)
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: interval) { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(analysis.map { fmtPrice($0.price, market: $0.market) } ?? "—")
                .font(.system(size: 38, weight: .bold).monospacedDigit()).foregroundStyle(Palette.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 10) {
                if let c = analysis?.changePct {
                    Text(fmtPct(c)).font(.headline.monospacedDigit()).foregroundStyle(c >= 0 ? Palette.buy : Palette.sell)
                }
                if let a = analysis { Pill(text: a.stance.word, fg: a.stance.fg, bg: a.stance.bg) }
                Spacer()
                Text(item.symbol).font(.footnote).foregroundStyle(Palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chartLevels(_ a: Analysis) -> [ChartLevel] {
        var out: [ChartLevel] = []
        if let e = a.entry { out.append(ChartLevel(label: "Entry", price: e, color: Palette.tint)) }
        if let s = a.stop { out.append(ChartLevel(label: "SL", price: s, color: Palette.sell)) }
        if let t = a.target1 { out.append(ChartLevel(label: "TP1", price: t, color: Palette.buy)) }
        if let t = a.target2 { out.append(ChartLevel(label: "TP2", price: t, color: Palette.buy.opacity(0.7))) }
        return out
    }

    private func levelsCard(_ a: Analysis) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Các mức giá cần chú ý", "Key price levels")).font(.headline).foregroundStyle(Palette.text)
                ForEach(chartLevels(a)) { l in
                    HStack {
                        Circle().fill(l.color).frame(width: 8, height: 8)
                        Text(levelName(l.label)).foregroundStyle(Palette.dim)
                        Spacer()
                        Text(fmtPrice(l.price, market: a.market)).font(.body.monospacedDigit()).foregroundStyle(Palette.text)
                        Text(fmtPct((l.price - a.price) / a.price * 100)).font(.footnote.monospacedDigit())
                            .foregroundStyle(Palette.muted).frame(width: 68, alignment: .trailing)
                    }
                }
                if let rr = a.rr, rr > 0 {
                    Divider()
                    Text(L("Lợi nhuận so với rủi ro khoảng 1 : ", "Reward to risk about 1 : ") + rr.formatted(.number.precision(.fractionLength(1))))
                        .font(.footnote).foregroundStyle(Palette.dim)
                }
            }
        }
    }

    private func levelName(_ k: String) -> String {
        switch k {
        case "Entry": return L("Vùng vào", "Entry")
        case "SL": return L("Cắt lỗ", "Stop")
        case "TP1": return L("Mục tiêu 1", "Target 1")
        default: return L("Mục tiêu 2", "Target 2")
        }
    }

    /// Ba con số người dùng cần nhất, vẽ thành thanh để so với nhau: giá hay nhúc nhích bao nhiêu, cắt lỗ thì mất bao nhiêu, mục tiêu được bao nhiêu.
    @ViewBuilder private func riskCard(_ a: Analysis) -> some View {
        let rows: [(String, String, Double?, Color)] = [
            (L("Biến động thường thấy", "Typical move"), L("mỗi nến", "per candle"), a.typicalMovePct, Palette.tint),
            (L("Rủi ro nếu cắt lỗ", "Risk to stop"), "SL", a.riskPct, Palette.sell),
            (L("Mục tiêu 1", "Target 1"), "TP", a.rewardPct, Palette.buy),
        ]
        let shown = rows.filter { $0.2 != nil }
        if !shown.isEmpty {
            let top = shown.compactMap { $0.2 }.max() ?? 1
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("Biến động và rủi ro", "Movement and risk")).font(.headline).foregroundStyle(Palette.text)
                    ForEach(shown, id: \.0) { r in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(r.0).foregroundStyle(Palette.dim)
                                Text(r.1).font(.caption).foregroundStyle(Palette.muted)
                                Spacer()
                                Text((r.2 ?? 0).formatted(.number.precision(.fractionLength(2))) + "%")
                                    .font(.body.monospacedDigit()).foregroundStyle(Palette.text)
                            }
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Palette.muted.opacity(0.15))
                                    Capsule().fill(r.3).frame(width: max(6, g.size.width * CGFloat((r.2 ?? 0) / top)))
                                }
                            }
                            .frame(height: 8)
                        }
                    }
                    Text(L("Ý nghĩa từng số: Cài đặt > Giới thiệu.", "What each number means: Settings > About."))
                        .font(.caption).foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private func readingCard(_ a: Analysis) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Đọc nhanh", "Quick read")).font(.headline).foregroundStyle(Palette.text)
                Text(summary(a)).font(.subheadline).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)
                if let c = a.confidence {
                    Text(L("Độ tin cậy: ", "Confidence: ") + confidenceName(c)).font(.subheadline).foregroundStyle(Palette.dim)
                }
            }
        }
    }

    private func summary(_ a: Analysis) -> String {
        let frame = L(frames.first { $0.0 == interval }?.1 ?? "", frames.first { $0.0 == interval }?.2 ?? "").lowercased()
        switch a.stance {
        case .up: return L("Trên khung \(frame), xu hướng đang nghiêng tăng.", "On the \(frame) frame the trend is leaning up.")
        case .down: return L("Trên khung \(frame), xu hướng đang nghiêng giảm.", "On the \(frame) frame the trend is leaning down.")
        case .steady: return L("Trên khung \(frame), giá đang đi ngang, chưa có hướng rõ.", "On the \(frame) frame price is moving sideways with no clear direction.")
        case .wait: return L("Trên khung \(frame), tín hiệu chưa đủ rõ. Đợi thêm sẽ an toàn hơn.", "On the \(frame) frame the signal isn't clear yet. Waiting is the safer read.")
        }
    }

    private func confidenceName(_ c: String) -> String {
        switch c.uppercased() {
        case "HIGH": return L("Cao", "High")
        case "MEDIUM", "MODERATE": return L("Vừa", "Medium")
        case "LOW": return L("Thấp", "Low")
        default: return c
        }
    }

    @ViewBuilder private func problemView(_ p: APIError) -> some View {
        Card {
            VStack(spacing: 10) {
                switch p.code {
                case .quota:
                    Label(L("Hôm nay vậy là đủ rồi, mai quay lại nhé.", "That's enough for today. Come back tomorrow."), systemImage: "moon.stars")
                case .locked:
                    Label(L("Mã này hiện chưa xem được.", "This one isn't available right now."), systemImage: "lock")
                case .offline, .timeout:
                    Label(L("Không có kết nối mạng.", "No connection."), systemImage: "wifi.slash")
                default:
                    Label(L("Có lỗi, thử lại giúp tôi.", "Something went wrong. Please try again."), systemImage: "exclamationmark.triangle")
                }
                if p.code != .quota && p.code != .locked {
                    Button(L("Thử lại", "Try again")) { Task { await load(force: true) } }.buttonStyle(.bordered)
                }
            }
            .font(.subheadline).foregroundStyle(Palette.dim).frame(maxWidth: .infinity)
        }
    }

    private func load(force: Bool = false) async {
        loading = true; problem = nil
        defer { loading = false }
        do {
            analysis = try await Service.analysis(symbol: item.symbol, market: item.market, interval: interval, force: force)
        } catch let e as APIError { analysis = nil; problem = e }
        catch { analysis = nil; problem = APIError(code: .server) }
    }
}
