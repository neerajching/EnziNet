import Foundation

public enum HTTPMethod: String, Sendable, Hashable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
    case options = "OPTIONS"

    /// Idempotent methods are safe to retry automatically.
    public var isIdempotent: Bool {
        switch self {
        case .get, .head, .put, .delete, .options: return true
        case .post, .patch: return false
        }
    }
}
