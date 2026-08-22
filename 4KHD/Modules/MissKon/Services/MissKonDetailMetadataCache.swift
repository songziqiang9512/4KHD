import Foundation

nonisolated struct MissKonDetailMetadata: Sendable {
    let mediaFireURL: URL?
}

/// MissKon-only HTML metadata. Image URLs stay in the shared detail-page cache;
/// source-specific fields stay behind the module boundary.
nonisolated final class MissKonDetailMetadataCache: @unchecked Sendable {
    static let shared = MissKonDetailMetadataCache()

    private struct Entry: Codable, Sendable {
        let mediaFireURL: URL?
        let updatedAt: Date
    }

    private let lock = NSLock()
    private let saveQueue = DispatchQueue(
        label: "com.songziqiang.4khd.misskon-detail-metadata-cache",
        qos: .utility
    )
    private let cacheURL: URL
    private let expirationInterval: TimeInterval = 7 * 24 * 60 * 60
    private let maxEntryCount = 500
    private var storage: [String: Entry]

    private init() {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheURL = supportDirectory
            .appendingPathComponent("4KHD/MissKon/DetailMetadata", isDirectory: true)
            .appendingPathComponent("pages.json")
        storage = Self.load(from: cacheURL)
        pruneExpired()
    }

    init(cacheURL: URL) {
        self.cacheURL = cacheURL
        storage = Self.load(from: cacheURL)
        pruneExpired()
    }

    func metadata(for pageURL: URL) -> MissKonDetailMetadata? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = storage[pageURL.absoluteString] else { return nil }
        guard Date().timeIntervalSince(entry.updatedAt) <= expirationInterval else {
            storage[pageURL.absoluteString] = nil
            scheduleSaveLocked()
            return nil
        }
        return MissKonDetailMetadata(mediaFireURL: entry.mediaFireURL)
    }

    func store(pageURL: URL, mediaFireURL: URL?) {
        lock.lock()
        storage[pageURL.absoluteString] = Entry(mediaFireURL: mediaFireURL, updatedAt: Date())
        trimLocked()
        scheduleSaveLocked()
        lock.unlock()
    }

    func flush() {
        let snapshot = snapshot()
        saveQueue.sync {
            Self.save(snapshot, to: cacheURL)
        }
    }

    func clear() async throws {
        resetStateForClear()
        try await withCheckedThrowingContinuation { continuation in
            saveQueue.async {
                do {
                    let directory = self.cacheURL.deletingLastPathComponent()
                    if FileManager.default.fileExists(atPath: directory.path) {
                        try FileManager.default.removeItem(at: directory)
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func resetStateForClear() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }

    private func pruneExpired() {
        lock.lock()
        let now = Date()
        storage = storage.filter { now.timeIntervalSince($0.value.updatedAt) <= expirationInterval }
        trimLocked()
        lock.unlock()
    }

    private func trimLocked() {
        guard storage.count > maxEntryCount else { return }
        let retained = storage
            .sorted { $0.value.updatedAt > $1.value.updatedAt }
            .prefix(maxEntryCount)
        storage = Dictionary(uniqueKeysWithValues: retained.map { ($0.key, $0.value) })
    }

    private func scheduleSaveLocked() {
        let snapshot = storage
        let cacheURL = cacheURL
        saveQueue.async {
            Self.save(snapshot, to: cacheURL)
        }
    }

    private func snapshot() -> [String: Entry] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    private static func load(from url: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    private static func save(_ snapshot: [String: Entry], to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            // Metadata cache failure must never fail image browsing.
        }
    }
}
