import Foundation

public enum RequestBody: Sendable {
    case data(Data, contentType: String?)
    /// Encoded with the client's `JSONEncoder` at send time.
    case encodable(@Sendable (JSONEncoder) throws -> Data)
    /// `application/x-www-form-urlencoded`
    case form([String: String])
    case multipart(MultipartFormData)

    public static func json<T: Encodable & Sendable>(_ value: T) -> RequestBody {
        .encodable { try $0.encode(value) }
    }

    func resolve(encoder: JSONEncoder) throws -> (data: Data, contentType: String?) {
        switch self {
        case let .data(d, type):
            return (d, type)
        case let .encodable(encode):
            do { return (try encode(encoder), "application/json") }
            catch { throw EnziError.encodingFailed(error) }
        case let .form(fields):
            let allowed: CharacterSet = {
                var s = CharacterSet.alphanumerics
                s.insert(charactersIn: "-._~")
                return s
            }()
            func esc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
            let str = fields.sorted { $0.key < $1.key }.map { "\(esc($0.key))=\(esc($0.value))" }.joined(separator: "&")
            return (Data(str.utf8), "application/x-www-form-urlencoded")
        case let .multipart(m):
            return (m.encoded(), m.contentType)
        }
    }
}
