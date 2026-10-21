import Foundation

/// A description of an HTTP call. Build it, hand it to a `NetworkClient`.
public struct Request: Sendable {
    public var path: String
    public var method: HTTPMethod
    public var query: [URLQueryItem]
    public var headers: [String: String]
    public var body: RequestBody?
    /// Overrides the client's default timeout.
    public var timeout: TimeInterval?
    /// When true (default) and the client has an `Authenticator`, credentials are attached.
    public var requiresAuth: Bool
    /// Overrides the client's default retry policy for this request.
    public var retryPolicy: RetryPolicy?

    public init(
        path: String,
        method: HTTPMethod = .get,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: RequestBody? = nil,
        timeout: TimeInterval? = nil,
        requiresAuth: Bool = true,
        retryPolicy: RetryPolicy? = nil
    ) {
        self.path = path
        self.method = method
        self.query = query
        self.headers = headers
        self.body = body
        self.timeout = timeout
        self.requiresAuth = requiresAuth
        self.retryPolicy = retryPolicy
    }
}

// MARK: - Conveniences

extension Request {
    private static func items(_ q: [String: String]) -> [URLQueryItem] {
        q.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    }

    public static func get(_ path: String, query: [String: String] = [:],
                           headers: [String: String] = [:], requiresAuth: Bool = true) -> Request {
        Request(path: path, method: .get, query: items(query), headers: headers, requiresAuth: requiresAuth)
    }

    public static func post(_ path: String, body: RequestBody? = nil, query: [String: String] = [:],
                            headers: [String: String] = [:], requiresAuth: Bool = true) -> Request {
        Request(path: path, method: .post, query: items(query), headers: headers, body: body, requiresAuth: requiresAuth)
    }

    public static func put(_ path: String, body: RequestBody? = nil,
                           headers: [String: String] = [:], requiresAuth: Bool = true) -> Request {
        Request(path: path, method: .put, headers: headers, body: body, requiresAuth: requiresAuth)
    }

    public static func patch(_ path: String, body: RequestBody? = nil,
                             headers: [String: String] = [:], requiresAuth: Bool = true) -> Request {
        Request(path: path, method: .patch, headers: headers, body: body, requiresAuth: requiresAuth)
    }

    public static func delete(_ path: String, headers: [String: String] = [:], requiresAuth: Bool = true) -> Request {
        Request(path: path, method: .delete, headers: headers, requiresAuth: requiresAuth)
    }
}
