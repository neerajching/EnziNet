import Foundation

public struct Response: Sendable {
    public let data: Data
    public let statusCode: Int
    public let headers: [String: String]
    public let url: URL?

    public init(data: Data, statusCode: Int, headers: [String: String] = [:], url: URL? = nil) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
        self.url = url
    }

    init(data: Data, http: HTTPURLResponse) {
        var h: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
            if let k = k as? String, let v = v as? String { h[k] = v }
        }
        self.init(data: data, statusCode: http.statusCode, headers: h, url: http.url)
    }

    /// Case-insensitive header lookup.
    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    public func decode<T: Decodable>(_ type: T.Type = T.self, using decoder: JSONDecoder = JSONDecoder()) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch { throw EnziError.decodingFailed(error, self) }
    }
}
