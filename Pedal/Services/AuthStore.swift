import Foundation
import Security

/// The session token, kept in the Keychain so it survives reinstall-free relaunches
/// and never lands in a plist backup. The server URL is not secret, so it lives in
/// UserDefaults next door.
@Observable
final class AuthStore {
    private static let service = "com.pedal.Pedal"
    private static let tokenAccount = "session-token"
    private static let userKey = "pedal.currentUser"
    private static let baseURLKey = "pedal.baseURL"

    private(set) var token: String?
    private(set) var user: User?

    var isLoggedIn: Bool { token != nil }

    /// Editable in Settings; the phone needs the laptop's LAN address, not localhost.
    var baseURL: String {
        get { UserDefaults.standard.string(forKey: Self.baseURLKey) ?? Config.defaultBaseURL }
        set {
            UserDefaults.standard.set(Self.normalize(newValue), forKey: Self.baseURLKey)
        }
    }

    init() {
        token = Self.keychainRead(account: Self.tokenAccount)
        if let data = UserDefaults.standard.data(forKey: Self.userKey) {
            user = try? JSONDecoder().decode(User.self, from: data)
        }
    }

    func signIn(token: String, user: User) {
        self.token = token
        self.user = user
        Self.keychainWrite(account: Self.tokenAccount, value: token)
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: Self.userKey)
        }
    }

    func update(user: User) {
        self.user = user
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: Self.userKey)
        }
    }

    func signOut() {
        token = nil
        user = nil
        Self.keychainDelete(account: Self.tokenAccount)
        UserDefaults.standard.removeObject(forKey: Self.userKey)
    }

    /// Accepts "192.168.1.4:3000" and turns it into a URL the app can use.
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if !s.isEmpty, !s.contains("://") { s = "http://" + s }
        return s
    }

    // MARK: - Keychain

    private static func keychainWrite(account: String, value: String) {
        keychainDelete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func keychainRead(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainDelete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
