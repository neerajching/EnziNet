import Foundation

public struct HTTPResult: Sendable {
    public var data: Data
    public var response: HTTPURLResponse
    public init(data: Data, response: HTTPURLResponse) {
        self.data = data
        self.response = response
    }
}

/// Per-call metadata shared with every interceptor in the chain.
public struct RequestContext: Sendable {
    public let id: UUID
    public let requiresAuth: Bool
    public let retryPolicy: RetryPolicy?

    public init(id: UUID = UUID(), requiresAuth: Bool = true, retryPolicy: RetryPolicy? = nil) {
        self.id = id
        self.requiresAuth = requiresAuth
        self.retryPolicy = retryPolicy
    }
}

public typealias Next = @Sendable (URLRequest) async throws -> HTTPResult

/// Chain-of-responsibility hook. You can:
///  - modify the request before calling `next`
///  - modify/inspect/replace the result after `next`
///  - call `next` several times (retry), or never (cache, short-circuit)
public protocol Interceptor: Sendable {
    func intercept(_ request: URLRequest, context: RequestContext, next: Next) async throws -> HTTPResult
}
