import Foundation

public struct EnziConfiguration {
    public var baseURL: URL?
    public var session: URLSession
    public var defaultHeaders: [String: String]
    public var authenticator: Authenticator?
    public var retryPolicy: RetryPolicy
    /// Outermost interceptors: they see ONE logical call, before retry/auth.
    public var interceptors: [Interceptor]
    /// Innermost interceptors: they see EVERY attempt, after retry/auth (ideal for logging).
    public var networkInterceptors: [Interceptor]
    public var encoder: JSONEncoder
    public var decoder: JSONDecoder
    public var timeout: TimeInterval
    public var validStatusCodes: Range<Int>

    public init(
        baseURL: URL? = nil,
        session: URLSession = URLSession(configuration: .default),
        defaultHeaders: [String: String] = ["Accept": "application/json"],
        authenticator: Authenticator? = nil,
        retryPolicy: RetryPolicy = .default,
        interceptors: [Interceptor] = [],
        networkInterceptors: [Interceptor] = [],
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        timeout: TimeInterval = 60,
        validStatusCodes: Range<Int> = 200..<300
    ) {
        self.baseURL = baseURL
        self.session = session
        self.defaultHeaders = defaultHeaders
        self.authenticator = authenticator
        self.retryPolicy = retryPolicy
        self.interceptors = interceptors
        self.networkInterceptors = networkInterceptors
        self.encoder = encoder
        self.decoder = decoder
        self.timeout = timeout
        self.validStatusCodes = validStatusCodes
    }
}
