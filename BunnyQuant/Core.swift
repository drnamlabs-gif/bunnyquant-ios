// Dr. Nam H. Le. drnamlabs.com, bunnyquant.com
import Foundation
import Observation
import Security

enum Lang: String { case vi, en }

/// Ngôn ngữ giao diện: theo máy, đổi được trong Cài đặt. Đọc `AppState.shared.lang` trong body nên giao diện tự vẽ lại.
@Observable
final class AppState {
    static let shared = AppState()
    var lang: Lang {
        didSet { UserDefaults.standard.set(lang.rawValue, forKey: "bq.lang") }
    }
    var signedInEmail: String?

    init() {
        if let s = UserDefaults.standard.string(forKey: "bq.lang"), let l = Lang(rawValue: s) { lang = l }
        else { lang = (Locale.preferredLanguages.first ?? "en").hasPrefix("vi") ? .vi : .en }
    }
}

func L(_ vi: String, _ en: String) -> String { AppState.shared.lang == .vi ? vi : en }

/// Lưu chuỗi nhỏ trong Keychain (khóa phiên, key App Attest). Không bao giờ dùng UserDefaults cho token.
enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.bunnyquant.app", kSecAttrAccount as String: key]
    }

    static func get(_ key: String) -> Data? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    static func set(_ key: String, _ data: Data?) {
        SecItemDelete(query(key) as CFDictionary)
        guard let data else { return }
        var q = query(key)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
}
