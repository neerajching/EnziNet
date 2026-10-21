import Foundation

public typealias ProgressHandler = @Sendable (TransferProgress) -> Void

/// Depend on this protocol in your apps so the client can be mocked in tests.
public protocol NetworkClient: Sendable {
    func send(_ request: Request) async throws -> Response
    func send<T: Decodable>(_ request: Request, as type: T.Type) async throws -> T
    func download(_ request: Request, to destination: URL, progress: ProgressHandler?) async throws -> URL
    func upload(_ request: Request, fromFile fileURL: URL, progress: ProgressHandler?) async throws -> Response
    func upload(_ request: Request, multipart: MultipartFormData, progress: ProgressHandler?) async throws -> Response
}

extension NetworkClient {
    public func send<T: Decodable>(_ request: Request) async throws -> T {
        try await send(request, as: T.self)
    }
    public func download(_ request: Request, to destination: URL) async throws -> URL {
        try await download(request, to: destination, progress: nil)
    }
    public func upload(_ request: Request, fromFile fileURL: URL) async throws -> Response {
        try await upload(request, fromFile: fileURL, progress: nil)
    }
    public func upload(_ request: Request, multipart: MultipartFormData) async throws -> Response {
        try await upload(request, multipart: multipart, progress: nil)
    }
}
