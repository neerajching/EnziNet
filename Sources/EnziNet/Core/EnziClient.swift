import Foundation

public final class EnziClient: NetworkClient, @unchecked Sendable {
    public let configuration: EnziConfiguration
    private let chain: [Interceptor]

    public init(configuration: EnziConfiguration) {
        self.configuration = configuration
        var chain = configuration.interceptors
        chain.append(RetryInterceptor(defaultPolicy: configuration.retryPolicy))
        if let auth = configuration.authenticator { chain.append(AuthInterceptor(authenticator: auth)) }
        chain.append(contentsOf: configuration.networkInterceptors)
        self.chain = chain
    }

    public convenience init(baseURL: URL) {
        self.init(configuration: EnziConfiguration(baseURL: baseURL))
    }

    // MARK: - Send

    public func send(_ request: Request) async throws -> Response {
        do {
            let urlRequest = try makeURLRequest(request)
            let context = RequestContext(requiresAuth: request.requiresAuth, retryPolicy: request.retryPolicy)
            let result = try await execute(0, urlRequest, context)
            let response = Response(data: result.data, http: result.response)
            try validate(response)
            return response
        } catch { throw Self.map(error) }
    }

    public func send<T: Decodable>(_ request: Request, as type: T.Type) async throws -> T {
        let response = try await send(request)
        return try response.decode(T.self, using: configuration.decoder)
    }

    // MARK: - Download

    public func download(_ request: Request, to destination: URL, progress: ProgressHandler?) async throws -> URL {
        do {
            let urlRequest = try makeURLRequest(request)
            let (staged, http) = try await authorized(urlRequest, requiresAuth: request.requiresAuth) { signed in
                try await self.performDownload(signed, progress: progress)
            }
            let fm = FileManager.default
            guard configuration.validStatusCodes.contains(http.statusCode) else {
                let body = (try? Data(contentsOf: staged)) ?? Data()
                try? fm.removeItem(at: staged)
                throw EnziError.httpStatus(Response(data: body, http: http))
            }
            do {
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.moveItem(at: staged, to: destination)
            } catch { throw EnziError.fileSystem(error) }
            return destination
        } catch { throw Self.map(error) }
    }

    // MARK: - Upload

    public func upload(_ request: Request, fromFile fileURL: URL, progress: ProgressHandler?) async throws -> Response {
        do {
            let urlRequest = try makeURLRequest(request)
            return try await uploadFile(urlRequest, file: fileURL, requiresAuth: request.requiresAuth, progress: progress)
        } catch { throw Self.map(error) }
    }

    public func upload(_ request: Request, multipart: MultipartFormData, progress: ProgressHandler?) async throws -> Response {
        do {
            var urlRequest = try makeURLRequest(request)
            urlRequest.setValue(multipart.contentType, forHTTPHeaderField: "Content-Type")
            // Write to disk so large payloads are streamed by URLSession, not held in the request.
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("enzi-upload-\(UUID().uuidString)")
            do { try multipart.encoded().write(to: tmp) } catch { throw EnziError.fileSystem(error) }
            defer { try? FileManager.default.removeItem(at: tmp) }
            return try await uploadFile(urlRequest, file: tmp, requiresAuth: request.requiresAuth, progress: progress)
        } catch { throw Self.map(error) }
    }

    // MARK: - Internals

    private func execute(_ index: Int, _ request: URLRequest, _ context: RequestContext) async throws -> HTTPResult {
        if index == chain.count { return try await transport(request) }
        return try await chain[index].intercept(request, context: context) { [self] req in
            try await self.execute(index + 1, req, context)
        }
    }

    private func transport(_ request: URLRequest) async throws -> HTTPResult {
        let (data, response) = try await configuration.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EnziError.invalidResponse }
        return HTTPResult(data: data, response: http)
    }

    private func validate(_ response: Response) throws {
        guard configuration.validStatusCodes.contains(response.statusCode) else {
            throw EnziError.httpStatus(response)
        }
    }

    func makeURLRequest(_ r: Request) throws -> URLRequest {
        let url: URL
        if let absolute = URL(string: r.path), absolute.scheme != nil {
            url = absolute
        } else {
            guard let base = configuration.baseURL else { throw EnziError.invalidURL(r.path) }
            let trimmed = String(r.path.drop(while: { $0 == "/" }))
            url = trimmed.isEmpty ? base : base.appendingPathComponent(trimmed)
        }
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw EnziError.invalidURL(url.absoluteString)
        }
        if !r.query.isEmpty { comps.queryItems = (comps.queryItems ?? []) + r.query }
        guard let finalURL = comps.url else { throw EnziError.invalidURL(url.absoluteString) }

        var req = URLRequest(url: finalURL, timeoutInterval: r.timeout ?? configuration.timeout)
        req.httpMethod = r.method.rawValue
        for (k, v) in configuration.defaultHeaders { req.setValue(v, forHTTPHeaderField: k) }
        for (k, v) in r.headers { req.setValue(v, forHTTPHeaderField: k) }
        if let body = r.body {
            let resolved = try body.resolve(encoder: configuration.encoder)
            req.httpBody = resolved.data
            if req.value(forHTTPHeaderField: "Content-Type") == nil, let type = resolved.contentType {
                req.setValue(type, forHTTPHeaderField: "Content-Type")
            }
        }
        return req
    }

    private func authorized<T>(
        _ request: URLRequest,
        requiresAuth: Bool,
        perform: (URLRequest) async throws -> (T, HTTPURLResponse)
    ) async throws -> (T, HTTPURLResponse) {
        if requiresAuth, let auth = configuration.authenticator {
            return try await AuthFlow.run(request, with: auth, perform: perform)
        }
        return try await perform(request)
    }

    private func uploadFile(_ request: URLRequest, file: URL, requiresAuth: Bool, progress: ProgressHandler?) async throws -> Response {
        let (data, http) = try await authorized(request, requiresAuth: requiresAuth) { signed in
            try await self.performUpload(signed, file: file, progress: progress)
        }
        let response = Response(data: data, http: http)
        try validate(response)
        return response
    }

    private func performDownload(_ request: URLRequest, progress: ProgressHandler?) async throws -> (URL, HTTPURLResponse) {
        let handle = TaskHandle()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(URL, HTTPURLResponse), Error>) in
                let task = configuration.session.downloadTask(with: request) { tmp, response, error in
                    handle.finish()
                    if let error { cont.resume(throwing: error); return }
                    guard let tmp, let http = response as? HTTPURLResponse else {
                        cont.resume(throwing: EnziError.invalidResponse); return
                    }
                    // The system deletes `tmp` when this handler returns, so move it now.
                    let staged = FileManager.default.temporaryDirectory.appendingPathComponent("enzi-dl-\(UUID().uuidString)")
                    do {
                        try FileManager.default.moveItem(at: tmp, to: staged)
                        cont.resume(returning: (staged, http))
                    } catch { cont.resume(throwing: EnziError.fileSystem(error)) }
                }
                if let progress {
                    handle.setObservation(task.progress.observe(\.fractionCompleted, options: [.new]) { p, _ in
                        progress(TransferProgress(completedBytes: p.completedUnitCount, totalBytes: p.totalUnitCount))
                    })
                }
                handle.attach(task)
                task.resume()
            }
        } onCancel: { handle.cancel() }
    }

    private func performUpload(_ request: URLRequest, file: URL, progress: ProgressHandler?) async throws -> (Data, HTTPURLResponse) {
        let handle = TaskHandle()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(Data, HTTPURLResponse), Error>) in
                let task = configuration.session.uploadTask(with: request, fromFile: file) { data, response, error in
                    handle.finish()
                    if let error { cont.resume(throwing: error); return }
                    guard let http = response as? HTTPURLResponse else {
                        cont.resume(throwing: EnziError.invalidResponse); return
                    }
                    cont.resume(returning: (data ?? Data(), http))
                }
                if let progress {
                    handle.setObservation(task.observe(\.countOfBytesSent, options: [.new]) { t, _ in
                        progress(TransferProgress(completedBytes: t.countOfBytesSent, totalBytes: t.countOfBytesExpectedToSend))
                    })
                }
                handle.attach(task)
                task.resume()
            }
        } onCancel: { handle.cancel() }
    }

    static func map(_ error: Error) -> Error {
        switch error {
        case let e as EnziError: return e
        case is CancellationError: return EnziError.cancelled
        case let e as URLError: return e.code == .cancelled ? EnziError.cancelled : EnziError.transport(e)
        default: return error   // custom interceptor/authenticator errors pass through untouched
        }
    }
}
