// Dr. Nam H. Le. drnamlabs.com, bunnyquant.com
import SwiftUI

/// Bảng màu lấy từ web (globals.css) và app cũ: teal -> blue là gradient thương hiệu. Chỉ có giao diện sáng.
enum Palette {
    static let bg = Color(hex: 0xF6F8FC)
    static let card = Color.white
    static let fill = Color(hex: 0xE9EFF7)
    static let line = Color(hex: 0xDCE4EE)
    static let text = Color(hex: 0x152133)
    static let dim = Color(hex: 0x4A5B72)
    static let muted = Color(hex: 0x63748A)
    static let brandA = Color(hex: 0x0F766E)
    static let brandB = Color(hex: 0x2563EB)
    static let tint = Color(hex: 0x1E6FD9)
    static let buy = Color(hex: 0x15803D), buySoft = Color(hex: 0xDCFCE7)
    static let sell = Color(hex: 0xB91C1C), sellSoft = Color(hex: 0xFEE2E2)
    static let hold = Color(hex: 0xB45309), holdSoft = Color(hex: 0xFEF3C7)
    static let wait = Color(hex: 0x2563EB), waitSoft = Color(hex: 0xDBEAFE)
    static let gradient = LinearGradient(colors: [brandA, brandB], startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255, opacity: 1)
    }
}

/// Hướng nhận định của máy chủ, nói bằng một từ dễ hiểu (không phải lệnh mua bán).
enum Stance: String {
    case up = "BUY", down = "SELL", steady = "HOLD", wait = "WAIT"

    init(_ raw: String) { self = Stance(rawValue: raw.uppercased()) ?? .wait }

    var word: String {
        switch self {
        case .up: return L("Nghiêng tăng", "Leaning up")
        case .down: return L("Nghiêng giảm", "Leaning down")
        case .steady: return L("Đứng yên", "Steady")
        case .wait: return L("Đang chờ", "Waiting")
        }
    }
    var fg: Color { self == .up ? Palette.buy : self == .down ? Palette.sell : self == .steady ? Palette.hold : Palette.wait }
    var bg: Color { self == .up ? Palette.buySoft : self == .down ? Palette.sellSoft : self == .steady ? Palette.holdSoft : Palette.waitSoft }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.line.opacity(0.7), lineWidth: 0.5))
    }
}

struct Pill: View {
    let text: String
    let fg: Color, bg: Color
    var body: some View {
        Text(text).font(.footnote.weight(.semibold)).foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(bg, in: Capsule())
    }
}

func fmtPrice(_ v: Double, market: String? = nil) -> String {
    let a = abs(v)
    let digits = market == "vn" ? 0 : a >= 1000 ? 2 : a >= 10 ? 2 : a >= 1 ? 3 : 5
    return v.formatted(.number.precision(.fractionLength(digits)).grouping(.automatic))
}

func fmtPct(_ v: Double) -> String {
    (v >= 0 ? "+" : "") + v.formatted(.number.precision(.fractionLength(2))) + "%"
}
