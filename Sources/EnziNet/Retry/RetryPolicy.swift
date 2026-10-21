import Foundation

public enum Backoff: Sendable {
    case none
    case constant(TimeInterval)
    /// delay = min(maxDelay, base * multiplier^(retry-1)); with jitter the delay is randomised in [d/2, d].
    case exponential(base: TimeInterval = 0.5, multiplier: Double = 2, maxDelay: TimeInterval = 30, jitter: Bool = true)

    /// `retry` starts at 1 for the first retry.
    func delay(forRetry retry: Int) -> TimeInterval {
        switch self {
        case .none: return 0
        case .constant(let d): return d
        case let .exponential(base, multiplier, maxDelay, jitter):
            let raw = min(maxDelay, base * pow(multiplier, Double(max(0, retry - 1))))
            return jitter ? raw / 2 + Double.random(in: 0...(raw / 2)) : raw
        }
    }
}

public struct RetryPolicy: Sendable {
    public var maxRetries: Int
    public var backoff: Backoff
    public var retryableStatusCodes: Set<Int>
    /// Defaults to idempotent methods only, so a POST is never duplicated by accident.
    public var retryableMethods: Set<HTTPMethod>
    public var retryableURLErrors: Set<URLError.Code>
    public var respectsRetryAfter: Bool

    public init(
        maxRetries: Int = 3,
        backoff: Backoff = .exponential(),
        retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504],
        retryableMethods: Set<HTTPMethod> = [.get, .head, .put, .delete, .options],
        retryableURLErrors: Set<URLError.Code> = [
            .timedOut, .networkConnectionLost, .notConnectedToInternet,
            .cannotConnectToHost, .dnsLookupFailed
        ],
        respectsRetryAfter: Bool = true
    ) {
        self.maxRetries = maxRetries
        self.backoff = backoff
        self.retryableStatusCodes = retryableStatusCodes
        self.retryableMethods = retryableMethods
        self.retryableURLErrors = retryableURLErrors
        self.respectsRetryAfter = respectsRetryAfter
    }

    public static let `default` = RetryPolicy()
    public static let none = RetryPolicy(maxRetries: 0)

    func allows(_ request: URLRequest) -> Bool {
        retryableMethods.contains(HTTPMethod(rawValue: request.httpMethod ?? "GET") ?? .get)
    }

    func shouldRetry(_ request: URLRequest, status: Int) -> Bool {
        allows(request) && retryableStatusCodes.contains(status)
    }

    func shouldRetry(_ request: URLRequest, error: URLError) -> Bool {
        allows(request) && retryableURLErrors.contains(error.code)
    }

    func delay(forRetry retry: Int, response: HTTPURLResponse?) -> TimeInterval {
        if respectsRetryAfter, let response,
           let header = response.value(forHTTPHeaderField: "Retry-After"),
           let server = Self.parseRetryAfter(header) {
            return min(max(server, 0), 60)
        }
        return backoff.delay(forRetry: retry)
    }

    static func parseRetryAfter(_ value: String) -> TimeInterval? {
        if let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)) { return seconds }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f.date(from: value).map { $0.timeIntervalSinceNow }
    }
}

struct RetryInterceptor: Interceptor {
    let defaultPolicy: RetryPolicy

    func intercept(_ request: URLRequest, context: RequestContext, next: Next) async throws -> HTTPResult {
        let policy = context.retryPolicy ?? defaultPolicy
        var retry = 0
        while true {
            do {
                let result = try await next(request)
                if retry < policy.maxRetries, policy.shouldRetry(request, status: result.response.statusCode) {
                    retry += 1
                    try await Self.sleep(policy.delay(forRetry: retry, response: result.response))
                    continue
                }
                return result
            } catch let error as URLError {
                guard retry < policy.maxRetries, policy.shouldRetry(request, error: error) else { throw error }
                retry += 1
                try await Self.sleep(policy.delay(forRetry: retry, response: nil))
            }
        }
    }

    private static func sleep(_ seconds: TimeInterval) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
