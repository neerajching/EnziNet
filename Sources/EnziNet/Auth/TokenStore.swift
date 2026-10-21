import Foundation
#if canImport(Security)
import Security
#endif

public protocol TokenStore: Sendable {
    func load() async -> AuthToken?
    func save(_ token: AuthToken?) async
}

public actor InMemoryTokenStore: TokenStore {
    private var token: AuthToken?
    public init(token: AuthToken? = nil) { self.token = token }
    public func load() async -> AuthToken? { token }
    public func save(_ token: AuthToken?) async { self.token = token }
}

#if canImport(Security)
/// Persists the token in the Keychain (available after first unlock).
public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    public init(service: String = "com.enziNet.auth", account: String = "default") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func load() async -> AuthToken? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(AuthToken.self, from: data)
    }

    public func save(_ token: AuthToken?) async {
        SecItemDelete(baseQuery as CFDictionary)
        guard let token, let data = try? JSONEncoder().encode(token) else { return }
        var q = baseQuery
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}
#endif
