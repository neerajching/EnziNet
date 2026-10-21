import Foundation
import os

/// Logs requests/responses through `os.Logger`. Put it in `networkInterceptors` to log every attempt.
/// Use `.headers`/`.body` in debug builds only: output is marked public.
public struct LoggingInterceptor: Interceptor {
    public enum Level: Sendable { case basic, headers, body }

    private let level: Level
    private let redacted: Set<String>
    private let logger: Logger
    
    private let redactedQueryKeys: Set<String> = ["token", "access_token", "api_key", "key", "password"]


    public init(level: Level = .basic,
                redactedHeaders: Set<String> = ["authorization", "cookie", "set-cookie"],
                subsystem: String = "com.enzinet") {
        self.level = level
        self.redacted = redactedHeaders
        self.logger = Logger(subsystem: subsystem, category: "Network")
    }

    public func intercept(_ request: URLRequest, context: RequestContext, next: Next) async throws -> HTTPResult {
        let tag = String(context.id.uuidString.prefix(8))
        let start = Date()
//        var line = "[\(tag)] → \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "?")"
//        
        var line = "[\(tag)] → \(request.httpMethod ?? "GET") \(safeURL(request.url))"
        
        if level != .basic { line += "\n" + format(request.allHTTPHeaderFields ?? [:]) }
        if level == .body, let b = request.httpBody { line += "\n" + preview(b) }
        logger.debug("\(line, privacy: .public)")

        do {
            let result = try await next(request)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            var out = "[\(tag)] ← \(result.response.statusCode) (\(ms) ms, \(result.data.count) bytes)"
            if level != .basic {
                let h = result.response.allHeaderFields.reduce(into: [String: String]()) {
                    if let k = $1.key as? String, let v = $1.value as? String { $0[k] = v }
                }
                out += "\n" + format(h)
            }
            if level == .body { out += "\n" + preview(result.data) }
            logger.debug("\(out, privacy: .public)")
            return result
        } catch {
            logger.error("[\(tag, privacy: .public)] ✕ \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func format(_ headers: [String: String]) -> String {
        headers.sorted { $0.key < $1.key }
            .map { "  \($0.key): \(redacted.contains($0.key.lowercased()) ? "<redacted>" : $0.value)" }
            .joined(separator: "\n")
    }

    private func preview(_ data: Data, limit: Int = 2048) -> String {
        let s = String(decoding: data.prefix(limit), as: UTF8.self)
        return data.count > limit ? s + "…(truncated)" : s
    }
    
    private func safeURL(_ url: URL?) -> String {
        guard let url, var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "?" }
        c.queryItems = c.queryItems?.map {
            redactedQueryKeys.contains($0.name.lowercased()) ? URLQueryItem(name: $0.name, value: "<redacted>") : $0
        }
        return c.url?.absoluteString ?? "?"
    }
}
