import Foundation

public protocol Authenticator: Sendable {
    /// Return a copy of `request` carrying credentials.
    func authenticate(_ request: URLRequest) async throws -> URLRequest
    /// Called on a 401. Return true if credentials were refreshed and the call should be retried once.
    func handleUnauthorized(for request: URLRequest, response: HTTPURLResponse) async throws -> Bool
}

extension Authenticator {
    public func handleUnauthorized(for request: URLRequest, response: HTTPURLResponse) async throws -> Bool { false }
}

/// Sign → perform → on 401 refresh → sign again → perform once more.
enum AuthFlow {
    static func run<T>(
        _ request: URLRequest,
        with authenticator: Authenticator,
        perform: (URLRequest) async throws -> (T, HTTPURLResponse)
    ) async throws -> (T, HTTPURLResponse) {
        let signed = try await sign(request, authenticator)
        let first = try await perform(signed)
        guard first.1.statusCode == 401 else { return first }

        let shouldRetry: Bool
        do { shouldRetry = try await authenticator.handleUnauthorized(for: signed, response: first.1) }
        catch { throw wrap(error) }
        guard shouldRetry else { return first }

        let resigned = try await sign(request, authenticator)
        return try await perform(resigned)
    }

    private static func sign(_ request: URLRequest, _ a: Authenticator) async throws -> URLRequest {
        do { return try await a.authenticate(request) } catch { throw wrap(error) }
    }

    private static func wrap(_ error: Error) -> Error {
        switch error {
        case is EnziError, is CancellationError, is URLError: return error
        default: return EnziError.authenticationFailed(error)
        }
    }
}

struct AuthInterceptor: Interceptor {
    let authenticator: Authenticator

    func intercept(_ request: URLRequest, context: RequestContext, next: Next) async throws -> HTTPResult {
        guard context.requiresAuth else { return try await next(request) }
        let (result, _) = try await AuthFlow.run(request, with: authenticator) { signed in
            let r = try await next(signed)
            return (r, r.response)
        }
        return result
    }
}
