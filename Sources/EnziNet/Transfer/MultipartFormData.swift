import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public struct MultipartFormData: Sendable {
    public struct Part: Sendable {
        public let name: String
        public let filename: String?
        public let mimeType: String?
        public let data: Data
    }

    public let boundary: String
    public private(set) var parts: [Part] = []

    public init(boundary: String = "Enzi-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public mutating func append(_ data: Data, name: String, filename: String? = nil, mimeType: String? = nil) {
        parts.append(Part(name: name, filename: filename, mimeType: mimeType, data: data))
    }

    public mutating func append(_ text: String, name: String) {
        append(Data(text.utf8), name: name)
    }

    /// Reads the file into memory. For very large files prefer `upload(_:fromFile:)`.
    public mutating func append(fileAt url: URL, name: String, mimeType: String? = nil) throws {
        let data = try Data(contentsOf: url)
        var mime = mimeType
        #if canImport(UniformTypeIdentifiers)
        if mime == nil { mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType }
        #endif
        append(data, name: name, filename: url.lastPathComponent, mimeType: mime ?? "application/octet-stream")
    }

    public func encoded() -> Data {
        var body = Data()
        let crlf = "\r\n"
        for part in parts {
            body.appendString("--\(boundary)\(crlf)")
            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let f = part.filename { disposition += "; filename=\"\(f)\"" }
            body.appendString(disposition + crlf)
            if let m = part.mimeType { body.appendString("Content-Type: \(m)\(crlf)") }
            body.appendString(crlf)
            body.append(part.data)
            body.appendString(crlf)
        }
        body.appendString("--\(boundary)--\(crlf)")
        return body
    }
}

private extension Data {
    mutating func appendString(_ s: String) { append(Data(s.utf8)) }
}
