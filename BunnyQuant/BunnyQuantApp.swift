// Dr. Nam H. Le. drnamlabs.com, bunnyquant.com
import SwiftUI

@main
struct BunnyQuantApp: App {
    var body: some Scene {
        WindowGroup {
            RootView().preferredColorScheme(.light)
        }
    }
}

/// Lần đầu mở: xin máy chủ một tài khoản riêng cho máy này (không hỏi email, mật khẩu), rồi vào danh sách.
struct RootView: View {
    enum Phase { case starting, ready, failed }
    @State private var phase = Phase.starting
    @State private var generation = 0
    private let app = AppState.shared

    var body: some View {
        Group {
            switch phase {
            case .ready: WatchlistView().id(generation)
            case .starting: Splash { ProgressView().tint(.white) }
            case .failed:
                Splash {
                    VStack(spacing: 14) {
                        Text(L("Chưa kết nối được. Kiểm tra mạng rồi thử lại.", "Couldn't connect. Check your network and try again."))
                            .multilineTextAlignment(.center).foregroundStyle(.white)
                        Button(L("Thử lại", "Try again")) { Task { await start() } }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(Palette.brandA)
                    }
                    .padding(32)
                }
            }
        }
        .task { await start() }
        .onReceive(NotificationCenter.default.publisher(for: .accountWiped)) { _ in
            generation += 1
            Task { await start() }
        }
    }

    private func start() async {
        phase = .starting
        do { _ = try await Auth.shared.accessToken(); app.signedInEmail = await Auth.shared.email; phase = .ready }
        catch { phase = .failed }
    }
}

private struct Splash<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Palette.gradient.ignoresSafeArea()
            VStack(spacing: 24) {
                Image("Mark").resizable().scaledToFit().frame(width: 96, height: 96)
                content
            }
        }
    }
}
