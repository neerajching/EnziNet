import Foundation

/// Adds headers that are not already set on the request (e.g. User-Agent, app version).
public struct HeaderInterceptor: Interceptor {
    private let headers: [String: String]
    public init(_ headers: [String: String]) { self.headers = headers }

    public func intercept(_ request: URLRequest, context: RequestContext, next: Next) async throws -> HTTPResult {
        var req = request
        for (k, v) in headers where req.value(forHTTPHeaderField: k) == nil {
            req.setValue(v, forHTTPHeaderField: k)
        }
        return try await next(req)
    }
}
