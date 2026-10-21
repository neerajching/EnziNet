import Foundation

/// Bearer-token auth with proactive refresh (token about to expire) and reactive refresh (401).
/// Concurrent refreshes are coalesced into ONE refresh call ("single flight").
public actor BearerAuthenticator: Authenticator {
    public typealias RefreshHandler = @Sendable (_ current: AuthToken) async throws -> AuthToken

    private let store: TokenStore
    private let refreshHandler: RefreshHandler?
    private var inFlight: Task<AuthToken, Error>?

    public init(store: TokenStore, refresh: RefreshHandler? = nil) {
        self.store = store
        self.refreshHandler = refresh
    }

    public func setToken(_ token: AuthToken?) async { await store.save(token) }
    public func signOut() async { await store.save(nil) }

    public func authenticate(_ request: URLRequest) async throws -> URLRequest {
        guard var token = await store.load() else { throw EnziError.missingCredentials }
        if token.isExpired(), token.refreshToken != nil, refreshHandler != nil {
            token = try await refresh(from: token)
        }
        var signed = request
        signed.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        return signed
    }

    public func handleUnauthorized(for request: URLRequest, response: HTTPURLResponse) async throws -> Bool {
        guard refreshHandler != nil, let current = await store.load() else { return false }
        // If the failed request used an older token, another call already refreshed: just retry.
        if request.value(forHTTPHeaderField: "Authorization") != "Bearer \(current.accessToken)" { return true }
        _ = try await refresh(from: current)
        return true
    }
    
    private func refresh(from token: AuthToken) async throws -> AuthToken {
        if let inFlight { return try await inFlight.value }
        guard let handler = refreshHandler else { return token }

        let store = self.store
        // Save INSIDE the task: waiters only resume after the new token is persisted.
        let task = Task {
            let fresh = try await handler(token)
            await store.save(fresh)
            return fresh
        }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}

/// Static header auth, e.g. API keys.
public struct HeaderAuthenticator: Authenticator {
    private let name: String
    private let value: String
    public init(name: String, value: String) { self.name = name; self.value = value }

    public func authenticate(_ request: URLRequest) async throws -> URLRequest {
        var r = request
        r.setValue(value, forHTTPHeaderField: name)
        return r
    }
}
