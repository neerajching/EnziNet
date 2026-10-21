import XCTest
@testable import EnziNet

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    @discardableResult func increment() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

struct User: Codable, Equatable, Sendable { let id: Int; let name: String }

final class EnziNetTests: XCTestCase {
    override func tearDown() { MockURLProtocol.handler = nil }

    private func makeClient(
        retry: RetryPolicy = .none,
        authenticator: Authenticator? = nil,
        interceptors: [Interceptor] = []
    ) -> EnziClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        var c = EnziConfiguration(
            baseURL: URL(string: "https://api.example.com/v1")!,
            session: URLSession(configuration: cfg),
            authenticator: authenticator,
            retryPolicy: retry,
            interceptors: interceptors
        )
        c.timeout = 5
        return EnziClient(configuration: c)
    }

    private func reply(_ req: URLRequest, _ status: Int, _ body: String = "{}") -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
    }

    func testDecodesJSONResponse() async throws {
        MockURLProtocol.handler = { self.reply($0, 200, #"{"id":1,"name":"Ada"}"#) }
        let user: User = try await makeClient().send(.get("/users/1"))
        XCTAssertEqual(user, User(id: 1, name: "Ada"))
    }

    func testBuildsURLWithBaseAndQuery() async throws {
        let seen = Counter()
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.absoluteString, "https://api.example.com/v1/users?page=2")
            seen.increment()
            return self.reply(req, 200)
        }
        _ = try await makeClient().send(.get("/users", query: ["page": "2"]))
        XCTAssertEqual(seen.value, 1)
    }

    func testRetriesOn503ThenSucceeds() async throws {
        let calls = Counter()
        MockURLProtocol.handler = { req in
            self.reply(req, calls.increment() < 3 ? 503 : 200)
        }
        let policy = RetryPolicy(maxRetries: 3, backoff: .constant(0.01))
        let response = try await makeClient(retry: policy).send(.get("/flaky"))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(calls.value, 3)
    }

    func testDoesNotRetryPOSTByDefault() async {
        let calls = Counter()
        MockURLProtocol.handler = { req in calls.increment(); return self.reply(req, 503) }
        let policy = RetryPolicy(maxRetries: 3, backoff: .constant(0.01))
        do {
            _ = try await makeClient(retry: policy).send(.post("/orders"))
            XCTFail("expected error")
        } catch let EnziError.httpStatus(response) {
            XCTAssertEqual(response.statusCode, 503)
        } catch { XCTFail("unexpected \(error)") }
        XCTAssertEqual(calls.value, 1)
    }

    func testRefreshesTokenOn401AndRetriesOnce() async throws {
        let calls = Counter()
        MockURLProtocol.handler = { req in
            calls.increment()
            let ok = req.value(forHTTPHeaderField: "Authorization") == "Bearer new"
            return self.reply(req, ok ? 200 : 401)
        }
        let auth = BearerAuthenticator(
            store: InMemoryTokenStore(token: AuthToken(accessToken: "old", refreshToken: "r")),
            refresh: { _ in AuthToken(accessToken: "new", refreshToken: "r") }
        )
        let response = try await makeClient(authenticator: auth).send(.get("/me"))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(calls.value, 2)
    }
    
    
    
    /// History: this originally failed with a 401. Waiting requests resumed as soon as
    /// the refresh finished, but before the new token was saved to the store, so they
    /// re-signed with the old token. Fixed by saving the token inside the shared
    /// refresh Task (see BearerAuthenticator.refresh(from:)).

    func testConcurrentRequestsShareOneRefresh() async throws {
        let refreshes = Counter()
        MockURLProtocol.handler = { req in
            self.reply(req, req.value(forHTTPHeaderField: "Authorization") == "Bearer new" ? 200 : 401)
        }
        let auth = BearerAuthenticator(
            store: InMemoryTokenStore(token: AuthToken(accessToken: "old", refreshToken: "r")),
            refresh: { _ in
                refreshes.increment()
                try await Task.sleep(nanoseconds: 50_000_000)
                return AuthToken(accessToken: "new", refreshToken: "r")
            }
        )
        let client = makeClient(authenticator: auth)
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<5 { group.addTask { try await client.send(.get("/me")).statusCode } }
            for try await code in group { XCTAssertEqual(code, 200) }
        }
        XCTAssertEqual(refreshes.value, 1)
    }

    func testInterceptorCanModifyRequest() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "X-App-Version"), "1.0")
            return self.reply(req, 200)
        }
        let client = makeClient(interceptors: [HeaderInterceptor(["X-App-Version": "1.0"])])
        _ = try await client.send(.get("/ping"))
    }

    func testMultipartEncoding() {
        var form = MultipartFormData(boundary: "B")
        form.append("hello", name: "greeting")
        let text = String(decoding: form.encoded(), as: UTF8.self)
        XCTAssertTrue(text.contains("--B\r\nContent-Disposition: form-data; name=\"greeting\"\r\n\r\nhello\r\n--B--"))
    }
}
