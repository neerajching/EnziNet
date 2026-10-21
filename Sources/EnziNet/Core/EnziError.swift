import Foundation

public enum EnziError: Error, LocalizedError, Sendable {
    case invalidURL(String)
    case encodingFailed(Error)
    case decodingFailed(Error, Response)
    /// The server answered with a status code outside `validStatusCodes`.
    case httpStatus(Response)
    case transport(URLError)
    case invalidResponse
    /// A request required auth but the authenticator had no credentials.
    case missingCredentials
    case authenticationFailed(Error)
    case fileSystem(Error)
    case cancelled

    public var statusCode: Int? {
        switch self {
        case .httpStatus(let r), .decodingFailed(_, let r): return r.statusCode
        default: return nil
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let s): return "Invalid URL: \(s)"
        case .encodingFailed(let e): return "Failed to encode request body: \(e.localizedDescription)"
        case .decodingFailed(let e, _): return "Failed to decode response: \(e.localizedDescription)"
        case .httpStatus(let r): return "Server returned HTTP \(r.statusCode)"
        case .transport(let e): return "Network error: \(e.localizedDescription)"
        case .invalidResponse: return "The server response was not a valid HTTP response"
        case .missingCredentials: return "No credentials available for an authenticated request"
        case .authenticationFailed(let e): return "Authentication failed: \(e.localizedDescription)"
        case .fileSystem(let e): return "File error: \(e.localizedDescription)"
        case .cancelled: return "The request was cancelled"
        }
    }
}
