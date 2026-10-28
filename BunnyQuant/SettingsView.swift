// Dr. Nam H. Le. drnamlabs.com, bunnyquant.com
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var app = AppState.shared
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var message: String?

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    var body: some View {
        NavigationStack {
            List {
                Section(L("Ngôn ngữ", "Language")) {
                    Picker("", selection: $app.lang) {
                        Text("Tiếng Việt").tag(Lang.vi)
                        Text("English").tag(Lang.en)
                    }
                    .pickerStyle(.segmented)
                }

                Section(L("Tài khoản", "Account")) {
                    if let mail = app.signedInEmail {
                        LabeledContent(L("Đã đăng nhập", "Signed in"), value: mail)
                        Button(L("Đăng xuất", "Sign out")) {
                            Task { await Auth.shared.signOut(); NotificationCenter.default.post(name: .accountChanged, object: nil) }
                        }
                    } else {
                        NavigationLink(L("Đăng nhập bằng tài khoản bunnyquant.com", "Sign in with a bunnyquant.com account")) { SignInView() }
                    }
                }

                Section {
                    Text(L("Chỉ là phân tích, không phải khuyến nghị đầu tư. Số liệu được ước lượng từ dữ liệu lịch sử và có thể sai. Quyết định và rủi ro là của bạn.",
                           "Analysis only, not investment advice. Figures are estimated from historical data and can be wrong. Decisions and risk are yours."))
                        .font(.footnote).foregroundStyle(Palette.dim)
                } header: { Text(L("Lưu ý", "Disclaimer")) }

                Section {
                    Explain(L("Biến động thường thấy", "Typical move"),
                            L("Giá thường dao động bao nhiêu phần trăm trong một nến (một giờ, một ngày hay một tuần tùy khung bạn chọn). Số càng lớn, giá càng hay nhảy.",
                              "How many percent price usually swings within one candle (an hour, a day or a week, depending on the frame). The bigger the number, the more the price jumps around."))
                    Explain(L("Điểm vào", "Entry"),
                            L("Vùng giá hợp lý để cân nhắc vào lệnh, tính từ cách giá đã chạy gần đây.",
                              "A reasonable price area to consider getting in, based on how price has been moving lately."))
                    Explain(L("Cắt lỗ (SL)", "Stop-loss (SL)"),
                            L("Mức giá mà nếu chạm tới thì kịch bản đã sai và nên thoát để giữ khoản lỗ trong tầm kiểm soát. Rủi ro là khoảng cách từ điểm vào tới mức này, tính bằng phần trăm.",
                              "The price at which the idea is wrong and you would step out to keep the loss under control. Risk is the distance from entry to this level, in percent."))
                    Explain(L("Chốt lời (TP)", "Take-profit (TP)"),
                            L("Mức giá mục tiêu để cân nhắc chốt lãi. Có hai mục tiêu: mục tiêu 1 gần hơn, mục tiêu 2 xa hơn.",
                              "A target price at which you might take profit. There are two: target 1 is closer, target 2 is further."))
                    Explain(L("Lợi nhuận so với rủi ro", "Reward to risk"),
                            L("Nếu số này là 1 : 2 thì lãi ở mục tiêu gấp khoảng hai lần khoản lỗ ở điểm cắt lỗ. Lớn hơn 1 là tốt hơn, nhưng không đảm bảo kết quả.",
                              "At 1 : 2 the gain at the target is about twice the loss at the stop. Above 1 is better, but nothing is guaranteed."))
                } header: { Text(L("Các con số nghĩa là gì", "What the numbers mean")) }

                Section(L("Giới thiệu", "About")) {
                    LabeledContent("BunnyQuant", value: version)
                    LabeledContent(L("Tác giả", "Developer"), value: "Dr. Nam H. Le")
                    Link("drnamlabs.com", destination: URL(string: "https://drnamlabs.com")!)
                    Link("bunnyquant.com", destination: URL(string: "https://bunnyquant.com")!)
                    Link(L("Quyền riêng tư", "Privacy"), destination: URL(string: "https://bunnyquant.com/privacy")!)
                    Text("© 2026 Dr. Nam H. Le. drnamlabs.com, bunnyquant.com").font(.caption).foregroundStyle(Palette.muted)
                }

                Section {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        if deleting { ProgressView() } else { Text(L("Xóa tài khoản và dữ liệu", "Delete account and data")) }
                    }
                    .disabled(deleting)
                } footer: {
                    Text(L("Xóa danh sách theo dõi và mọi dữ liệu của tài khoản này khỏi máy chủ.", "Removes your watchlist and all data of this account from the server."))
                }
            }
            .navigationTitle(L("Cài đặt", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L("Xong", "Done")) { dismiss() } } }
            .confirmationDialog(L("Xóa tài khoản?", "Delete account?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(L("Xóa vĩnh viễn", "Delete permanently"), role: .destructive) { Task { await deleteAccount() } }
                Button(L("Hủy", "Cancel"), role: .cancel) {}
            } message: { Text(L("Việc này không hoàn tác được.", "This can't be undone.")) }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func deleteAccount() async {
        deleting = true; defer { deleting = false }
        do {
            _ = try await API.call("/api/account", method: "DELETE")
            let wasAccount = await Auth.shared.hasAccount()
            if wasAccount {
                // Tài khoản bunnyquant.com đã xóa; tài khoản riêng của máy này vẫn dùng tiếp.
                await Auth.shared.signOut()
                NotificationCenter.default.post(name: .accountChanged, object: nil)
                dismiss()
            } else {
                await Auth.shared.wipe()
                ResultCache.clear()
                UserDefaults.standard.removeObject(forKey: "bq.seeded")
                UserDefaults.standard.removeObject(forKey: "bq.names")
                NotificationCenter.default.post(name: .accountWiped, object: nil)
                dismiss()
            }
        } catch let e as APIError where e.code == .billing {
            message = L("Tài khoản này đang có thanh toán trên bunnyquant.com. Hãy dừng ở đó trước, rồi xóa lại.",
                        "This account has active billing on bunnyquant.com. Stop it there first, then delete again.")
        } catch {
            message = L("Chưa xóa được, thử lại giúp tôi.", "Couldn't delete. Please try again.")
        }
    }
}

struct SignInView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField(L("Mật khẩu", "Password"), text: $password).textContentType(.password)
            } footer: {
                Text(L("Dùng tài khoản bạn đã tạo trên bunnyquant.com. Không bắt buộc.", "Use the account you created on bunnyquant.com. Optional."))
            }
            if let error { Text(error).font(.footnote).foregroundStyle(Palette.sell) }
            Button {
                Task { await signIn() }
            } label: {
                HStack { Spacer(); if busy { ProgressView() } else { Text(L("Đăng nhập", "Sign in")).bold() }; Spacer() }
            }
            .disabled(busy || email.isEmpty || password.isEmpty)
        }
        .navigationTitle(L("Đăng nhập", "Sign in"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func signIn() async {
        busy = true; error = nil; defer { busy = false }
        do {
            try await Auth.shared.signIn(email: email, password: password)
            NotificationCenter.default.post(name: .accountChanged, object: nil)
            dismiss()
        } catch let e as APIError where e.code == .unauthorized {
            error = L("Email hoặc mật khẩu chưa đúng.", "Email or password isn't right.")
        } catch let e as APIError where e.code == .offline || e.code == .timeout {
            error = L("Không có kết nối mạng.", "No connection.")
        } catch {
            self.error = L("Chưa đăng nhập được, thử lại giúp tôi.", "Couldn't sign in. Please try again.")
        }
    }
}


private struct Explain: View {
    let title: String, text: String
    init(_ title: String, _ text: String) { self.title = title; self.text = text }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
            Text(text).font(.footnote).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
