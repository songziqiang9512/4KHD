import Foundation
import Network

/// Loopback HTTP proxy for HLS playback that needs Referer (糖心Vlog).
///
/// AVPlayer rejects custom-scheme `.ts` with CoreMedia `-12881`
/// ("custom url not redirect"). Serving playlist and segments as
/// `http://127.0.0.1` lets the player use real HTTP while this process
/// still attaches Safari UA / Referer and decrypts AES-128 MPEG-TS.
final nonisolated class OnlineHLSLocalProxy: @unchecked Sendable {
    static let shared = OnlineHLSLocalProxy()
    static let playlistContentType = "application/vnd.apple.mpegurl"
    static let pathPrefix = "khd"

    private struct Session {
        let source: OnlineSourcePolicy.Source
        let userAgent: String
        let referer: String
        var aesKey: Data?
        var aesDefaultIV: Data?
        var aesIVByURL: [URL: Data] = [:]
    }

    private let queue = DispatchQueue(label: "com.4khd.hls-proxy")
    private var listener: NWListener?
    private var port: UInt16?
    private var sessions: [UUID: Session] = [:]
    private let httpSession: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 600
        httpSession = URLSession(
            configuration: configuration,
            delegate: OnlineRedirectGuard.shared,
            delegateQueue: nil
        )
    }

    func preparePlayback(
        mediaURL: URL,
        source: OnlineSourcePolicy.Source,
        userAgent: String,
        referer: String
    ) async throws -> (url: URL, sessionID: UUID) {
        try OnlineSourcePolicy.validate(mediaURL, source: source, resource: .media)
        let port = try await listeningPort()
        let sessionID = UUID()
        await mutate {
            $0.sessions[sessionID] = Session(source: source, userAgent: userAgent, referer: referer)
        }
        guard let url = Self.localMediaURL(from: mediaURL, sessionID: sessionID, port: port) else {
            endSession(sessionID)
            throw URLError(.badURL)
        }
        return (url, sessionID)
    }

    func endSession(_ sessionID: UUID) {
        queue.async { self.sessions[sessionID] = nil }
    }

    static func localMediaURL(from mediaURL: URL, sessionID: UUID, port: UInt16) -> URL? {
        guard mediaURL.scheme?.lowercased() == "https",
              let host = mediaURL.host,
              !host.isEmpty
        else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        let trimmed = mediaURL.path.hasPrefix("/") ? String(mediaURL.path.dropFirst()) : mediaURL.path
        components.path = "/\(pathPrefix)/\(sessionID.uuidString)/\(host)/\(trimmed)"
        components.query = mediaURL.query
        return components.url
    }

    static func remoteMediaURL(from localURL: URL) -> (sessionID: UUID, mediaURL: URL)? {
        let parts = localURL.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 4,
              parts[0] == pathPrefix,
              let sessionID = UUID(uuidString: parts[1])
        else { return nil }
        let host = parts[2]
        let rest = parts.dropFirst(3).joined(separator: "/")
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/\(rest)"
        components.query = localURL.query
        guard let mediaURL = components.url else { return nil }
        return (sessionID, mediaURL)
    }

    static func playlistByRemovingKeyTags(_ playlist: String) -> String {
        playlist
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                !line.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("#EXT-X-KEY:")
            }
            .joined(separator: "\n")
    }

    static func rewriteAbsoluteMediaURIs(
        in playlist: String,
        playlistURL: URL,
        sessionID: UUID,
        port: UInt16,
        source: OnlineSourcePolicy.Source
    ) -> String {
        playlistByRemovingKeyTags(playlist)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { raw in
                rewriteLine(String(raw), playlistURL: playlistURL, sessionID: sessionID, port: port, source: source)
            }
            .joined(separator: "\n")
    }

    private static func rewriteLine(
        _ line: String,
        playlistURL: URL,
        sessionID: UUID,
        port: UInt16,
        source: OnlineSourcePolicy.Source
    ) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { return line }
        guard trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://"),
              let resolved = URL(string: trimmed, relativeTo: playlistURL)?.absoluteURL,
              OnlineSourcePolicy.allows(resolved, source: source, resource: .media),
              let local = localMediaURL(from: resolved, sessionID: sessionID, port: port)
        else { return line }
        return local.absoluteString
    }

    private func listeningPort() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            queue.async {
                if let port = self.port {
                    continuation.resume(returning: port)
                    return
                }
                self.startListener(continuation)
            }
        }
    }

    private func mutate(_ body: @escaping @Sendable (OnlineHLSLocalProxy) -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                body(self)
                continuation.resume()
            }
        }
    }

    private func startListener(_ continuation: CheckedContinuation<UInt16, Error>) {
        if let port {
            continuation.resume(returning: port)
            return
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .loopback
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            continuation.resume(throwing: error)
            return
        }
        self.listener = listener
        let box = ContinuationBox(continuation)
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                guard let port = listener.port?.rawValue else {
                    box.resume(throwing: URLError(.cannotConnectToHost))
                    return
                }
                self?.queue.async {
                    self?.port = port
                    box.resume(returning: port)
                }
            case let .failed(error):
                box.resume(throwing: error)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.receiveRequest(on: connection, buffer: Data())
        }
        listener.start(queue: queue)
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                self.fulfill(connection: connection, header: buffer.prefix(upTo: headerEnd.lowerBound))
                return
            }
            if isComplete || error != nil || buffer.count > 64 * 1024 {
                connection.cancel()
                return
            }
            self.receiveRequest(on: connection, buffer: buffer)
        }
    }

    private func fulfill(connection: NWConnection, header: Data) {
        guard let text = String(data: header, encoding: .utf8) else {
            send(connection, status: 400, reason: "Bad Request", contentType: "text/plain", body: Data())
            return
        }
        let lines = text.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else {
            send(connection, status: 400, reason: "Bad Request", contentType: "text/plain", body: Data())
            return
        }
        let tokens = requestLine.split(separator: " ")
        guard tokens.count >= 2 else {
            send(connection, status: 400, reason: "Bad Request", contentType: "text/plain", body: Data())
            return
        }
        let method = String(tokens[0]).uppercased()
        guard method == "GET" || method == "HEAD" else {
            send(connection, status: 405, reason: "Method Not Allowed", contentType: "text/plain", body: Data())
            return
        }
        let target = String(tokens[1])
        let rangeHeader = lines
            .dropFirst()
            .first { $0.lowercased().hasPrefix("range:") }
            .map { String($0) }
        guard let localURL = URL(string: "http://127.0.0.1\(target)"),
              let parsed = Self.remoteMediaURL(from: localURL),
              let session = sessions[parsed.sessionID],
              let port
        else {
            send(connection, status: 404, reason: "Not Found", contentType: "text/plain", body: Data())
            return
        }
        do {
            try OnlineSourcePolicy.validate(parsed.mediaURL, source: session.source, resource: .media)
        } catch {
            send(connection, status: 403, reason: "Forbidden", contentType: "text/plain", body: Data())
            return
        }

        queue.async {
            self.fetchAndRespond(
                connection: connection,
                mediaURL: parsed.mediaURL,
                sessionID: parsed.sessionID,
                session: session,
                port: port,
                rangeHeader: rangeHeader,
                headOnly: method == "HEAD"
            )
        }
    }

    private func fetchAndRespond(
        connection: NWConnection,
        mediaURL: URL,
        sessionID: UUID,
        session: Session,
        port: UInt16,
        rangeHeader: String?,
        headOnly: Bool
    ) {
        var request = URLRequest(url: mediaURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
        request.setValue(session.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(session.referer, forHTTPHeaderField: "Referer")
        if let origin = OnlineSourcePolicy.originHeader(fromReferer: session.referer) {
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }
        let pathExtension = mediaURL.pathExtension.lowercased()
        switch pathExtension {
        case "m3u8":
            request.setValue(
                "application/vnd.apple.mpegurl,application/x-mpegURL,audio/mpegurl,*/*;q=0.8",
                forHTTPHeaderField: "Accept"
            )
        case "ts":
            request.setValue("video/mp2t,application/octet-stream;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        default:
            request.setValue("application/octet-stream,*/*;q=0.8", forHTTPHeaderField: "Accept")
        }

        let task = httpSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self else {
                connection.cancel()
                return
            }
            self.queue.async {
                self.completeFetch(
                    connection: connection,
                    mediaURL: mediaURL,
                    sessionID: sessionID,
                    port: port,
                    rangeHeader: rangeHeader,
                    headOnly: headOnly,
                    data: data,
                    response: response,
                    error: error
                )
            }
        }
        task.resume()
    }

    private func completeFetch(
        connection: NWConnection,
        mediaURL: URL,
        sessionID: UUID,
        port: UInt16,
        rangeHeader: String?,
        headOnly: Bool,
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) {
        if let error {
            send(connection, status: 502, reason: "Bad Gateway", contentType: "text/plain", body: Data(error.localizedDescription.utf8))
            return
        }
        guard var session = sessions[sessionID] else {
            send(connection, status: 404, reason: "Not Found", contentType: "text/plain", body: Data())
            return
        }
        do {
            guard let response else { throw URLError(.badServerResponse) }
            try OnlineSourcePolicy.validate(response, source: session.source, resource: .media)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 502
                send(connection, status: status, reason: "Upstream Error", contentType: "text/plain", body: Data())
                return
            }
            guard let data, !data.isEmpty else { throw URLError(.zeroByteResource) }
            let pathExtension = mediaURL.pathExtension.lowercased()
            if pathExtension == "m3u8" {
                let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                if let aes = KnitHLSPlaylist.playbackAES128(text, baseURL: mediaURL, source: session.source) {
                    session.aesDefaultIV = aes.defaultIV
                    session.aesIVByURL = aes.ivByURL
                    if session.aesKey == nil {
                        session.aesKey = try loadKey(aes.keyURL, session: session)
                    }
                    sessions[sessionID] = session
                }
                let rewritten = Self.rewriteAbsoluteMediaURIs(
                    in: text,
                    playlistURL: mediaURL,
                    sessionID: sessionID,
                    port: port,
                    source: session.source
                )
                send(
                    connection,
                    status: 200,
                    reason: "OK",
                    contentType: Self.playlistContentType,
                    body: Data(rewritten.utf8),
                    rangeHeader: rangeHeader,
                    headOnly: headOnly
                )
                return
            }

            var body = data
            var contentType = "application/octet-stream"
            if pathExtension == "ts" {
                if let key = session.aesKey {
                    let iv = session.aesIVByURL[mediaURL] ?? session.aesDefaultIV
                    guard let iv else { throw URLError(.cannotDecodeContentData) }
                    body = try KnitHLSAES128.decrypt(data, key: key, iv: iv)
                    body = (try? KnitVideoRemux.mpegTransportStreamAligned(body)) ?? body
                }
                contentType = "video/mp2t"
            }
            send(
                connection,
                status: 200,
                reason: "OK",
                contentType: contentType,
                body: body,
                rangeHeader: rangeHeader,
                headOnly: headOnly
            )
        } catch {
            send(connection, status: 502, reason: "Bad Gateway", contentType: "text/plain", body: Data())
        }
    }

    private func loadKey(_ keyURL: URL, session: Session) throws -> Data {
        try OnlineSourcePolicy.validate(keyURL, source: session.source, resource: .media)
        var request = URLRequest(url: keyURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
        request.setValue(session.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(session.referer, forHTTPHeaderField: "Referer")
        if let origin = OnlineSourcePolicy.originHeader(fromReferer: session.referer) {
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }
        request.setValue("application/octet-stream,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error> = .failure(URLError(.cannotDecodeContentData))
        httpSession.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                result = .failure(error)
                return
            }
            do {
                guard let response else { throw URLError(.badServerResponse) }
                try OnlineSourcePolicy.validate(response, source: session.source, resource: .media)
                guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
                      let data, data.count == 16
                else { throw URLError(.cannotDecodeContentData) }
                result = .success(data)
            } catch {
                result = .failure(error)
            }
        }.resume()
        semaphore.wait()
        return try result.get()
    }

    private func send(
        _ connection: NWConnection,
        status: Int,
        reason: String,
        contentType: String,
        body: Data,
        rangeHeader: String? = nil,
        headOnly: Bool = false
    ) {
        let payload: Data
        let statusToSend: Int
        let extraHeaders: String
        if status == 200, let range = parsedByteRange(rangeHeader, count: body.count) {
            payload = body.subdata(in: range)
            statusToSend = 206
            extraHeaders = "Content-Range: bytes \(range.lowerBound)-\(range.upperBound - 1)/\(body.count)\r\n"
        } else {
            payload = body
            statusToSend = status
            extraHeaders = ""
        }
        var header = "HTTP/1.1 \(statusToSend) \(statusToSend == 206 ? "Partial Content" : reason)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(payload.count)\r\n"
        header += extraHeaders
        header += "Connection: close\r\n\r\n"
        var message = Data(header.utf8)
        if !headOnly {
            message.append(payload)
        }
        connection.send(content: message, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func parsedByteRange(_ header: String?, count: Int) -> Range<Int>? {
        guard let header, count > 0 else { return nil }
        let lowered = header.lowercased()
        guard let bytesIndex = lowered.range(of: "bytes=") else { return nil }
        let spec = String(lowered[bytesIndex.upperBound...]).trimmingCharacters(in: .whitespaces)
        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let start = Int(parts[0]) else { return nil }
        let end: Int
        if parts.count == 2, let parsedEnd = Int(parts[1]) {
            end = min(parsedEnd + 1, count)
        } else {
            end = count
        }
        guard start >= 0, start < end, end <= count else { return nil }
        return start ..< end
    }

    private final nonisolated class ContinuationBox<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Error>?

        init(_ continuation: CheckedContinuation<T, Error>) {
            self.continuation = continuation
        }

        func resume(returning value: T) {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(returning: value)
        }

        func resume(throwing error: Error) {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(throwing: error)
        }
    }
}
