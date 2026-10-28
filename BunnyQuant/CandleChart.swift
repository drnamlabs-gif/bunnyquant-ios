// Dr. Nam H. Le. drnamlabs.com, bunnyquant.com
import SwiftUI

struct ChartLevel: Identifiable {
    let label: String
    let price: Double
    let color: Color
    var id: String { label }
}

/// Biểu đồ nến vẽ bằng Canvas (không dùng web view): nến, vạch Entry / SL / TP và nhãn giá bên phải.
struct CandleChart: View {
    let candles: [Candle]
    let levels: [ChartLevel]
    var maxBars = 70

    var body: some View {
        Canvas { ctx, size in
            let bars = Array(candles.suffix(maxBars))
            guard bars.count >= 2 else { return }
            let axisW: CGFloat = 58
            let plot = CGRect(x: 0, y: 6, width: size.width - axisW, height: size.height - 12)

            var lo = bars.map(\.l).min()!, hi = bars.map(\.h).max()!
            let span = hi - lo
            // Vạch xa nến quá thì bỏ, nếu không nến bị ép thành một đường mỏng.
            let shown = levels.filter { $0.price > lo - span * 0.9 && $0.price < hi + span * 0.9 }
            for l in shown { lo = min(lo, l.price); hi = max(hi, l.price) }
            let pad = (hi - lo) * 0.06
            lo -= pad; hi += pad
            func y(_ p: Double) -> CGFloat { plot.minY + plot.height * CGFloat((hi - p) / (hi - lo)) }

            // Lưới ngang mờ + giá
            for i in 0...3 {
                let p = lo + (hi - lo) * Double(i) / 3
                var g = Path(); g.move(to: CGPoint(x: 0, y: y(p))); g.addLine(to: CGPoint(x: plot.maxX, y: y(p)))
                ctx.stroke(g, with: .color(Palette.line.opacity(0.6)), lineWidth: 0.5)
                ctx.draw(Text(fmtPrice(p)).font(.system(size: 9).monospacedDigit()).foregroundStyle(Palette.muted),
                         at: CGPoint(x: plot.maxX + 4, y: y(p)), anchor: .leading)
            }

            // Nến
            let step = plot.width / CGFloat(bars.count)
            let w = max(1.5, step * 0.62)
            for (i, b) in bars.enumerated() {
                let x = plot.minX + step * (CGFloat(i) + 0.5)
                let up = b.c >= b.o
                let color = up ? Palette.buy : Palette.sell
                var wick = Path(); wick.move(to: CGPoint(x: x, y: y(b.h))); wick.addLine(to: CGPoint(x: x, y: y(b.l)))
                ctx.stroke(wick, with: .color(color), lineWidth: 1)
                let top = y(max(b.o, b.c)), bottom = y(min(b.o, b.c))
                ctx.fill(Path(CGRect(x: x - w / 2, y: top, width: w, height: max(1, bottom - top))), with: .color(color))
            }

            // Vạch các mức giá
            for l in shown {
                var line = Path(); line.move(to: CGPoint(x: 0, y: y(l.price))); line.addLine(to: CGPoint(x: plot.maxX, y: y(l.price)))
                ctx.stroke(line, with: .color(l.color), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                let tag = Text(l.label).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                let r = CGRect(x: plot.maxX + 2, y: y(l.price) - 7, width: axisW - 4, height: 14)
                ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(l.color))
                ctx.draw(tag, at: CGPoint(x: r.midX, y: r.midY), anchor: .center)
            }
        }
        .frame(height: 280)
        .accessibilityLabel(L("Biểu đồ nến", "Candlestick chart"))
    }
}
