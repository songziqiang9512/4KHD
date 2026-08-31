import Foundation
import Nuke

/// Lets a module rewrite image bytes after download (and after disk-cache hits)
/// without replacing the shared Nuke pipeline. Unmatched URLs keep the original
/// body so progressive JPEG and other sources are unchanged.
enum RemoteImageResponseMapper {
    struct Record {
        let matches: @Sendable (URL) -> Bool
        let map: @Sendable (Data) -> Data?
    }

    private nonisolated static let lock = NSLock()
    private nonisolated(unsafe) static var records: [Record] = []

    nonisolated static func register(_ record: Record) {
        lock.lock()
        records.append(record)
        lock.unlock()
    }

    nonisolated static func matches(_ url: URL) -> Bool {
        lock.lock()
        let snapshot = records
        lock.unlock()
        return snapshot.contains { $0.matches(url) }
    }

    /// Returns original data when no mapper claims the URL. Returns `nil` when a
    /// mapper claims the URL but cannot produce a usable body.
    nonisolated static func mappedData(for url: URL, from data: Data) -> Data? {
        lock.lock()
        let snapshot = records
        lock.unlock()
        guard let record = snapshot.first(where: { $0.matches(url) }) else { return data }
        return record.map(data)
    }
}

/// Buffers claimed responses so a mapper can see the complete body, then emits
/// the mapped bytes once. Other URLs pass through unchanged.
final class RemoteImageMappingDataLoader: DataLoading, @unchecked Sendable {
    private let inner: any DataLoading

    nonisolated init(inner: any DataLoading) {
        self.inner = inner
    }

    nonisolated func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable {
        guard let url = request.url, RemoteImageResponseMapper.matches(url) else {
            return inner.loadData(with: request, didReceiveData: didReceiveData, completion: completion)
        }
        let buffer = Buffer()
        return inner.loadData(
            with: request,
            didReceiveData: { data, response in
                buffer.append(data, response: response)
            },
            completion: { error in
                if let error {
                    completion(error)
                    return
                }
                guard let response = buffer.response else {
                    completion(URLError(.badServerResponse))
                    return
                }
                guard let mapped = RemoteImageResponseMapper.mappedData(for: url, from: buffer.data) else {
                    completion(URLError(.cannotDecodeContentData))
                    return
                }
                didReceiveData(mapped, response)
                completion(nil)
            }
        )
    }
}

private final class Buffer: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var chunks = Data()
    private nonisolated(unsafe) var storedResponse: URLResponse?

    nonisolated var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return chunks
    }

    nonisolated var response: URLResponse? {
        lock.lock()
        defer { lock.unlock() }
        return storedResponse
    }

    nonisolated func append(_ data: Data, response: URLResponse) {
        lock.lock()
        chunks.append(data)
        storedResponse = response
        lock.unlock()
    }
}
