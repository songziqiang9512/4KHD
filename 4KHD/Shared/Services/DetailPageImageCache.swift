import Foundation
import OSLog

struct CachedDetailImagePage: Sendable {
    let pageURL: URL
    let imageURLs: [URL]
    let pageURLs: [URL]
}

nonisolated final class DetailPageImageCache: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.songziqiang.4khd", category: "DetailPageCache")
    static let shared = DetailPageImageCache()

    private struct Entry: Codable, Sendable {
        let pageURL: URL
        let imageURLs: [URL]
        let pageURLs: [URL]
        var updatedAt: Date
        var isPersistent: Bool
    }

    private let lock = NSLock()
    private let saveQueue = DispatchQueue(label: "com.songziqiang.4khd.detail-page-cache-save", qos: .utility)
    private let cacheURL: URL
    private let expirationInterval: TimeInterval = 7 * 24 * 60 * 60
    private let maxVolatileEntryCount = 500
    private let maxPersistentEntryCount = 800
    private var storage: [String: Entry] = [:]
    private var cachedDetailPaths = Set<String>()
    private var loadGeneration = 0
    private var persistentOverrides: [String: Bool] = [:]
    private var pendingSaveWorkItem: DispatchWorkItem?

    private init() {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = supportDirectory.appendingPathComponent("4KHD/DetailPageCache", isDirectory: true)
        cacheURL = directory.appendingPathComponent("pages.json")
        scheduleInitialLoad()
    }

    init(cacheURL: URL) {
        self.cacheURL = cacheURL
        scheduleInitialLoad()
    }

    func urls(for pageURL: URL) -> ResolvedImagePage? {
        page(for: pageURL).map {
            ResolvedImagePage(pageURL: $0.pageURL, imageURLs: $0.imageURLs, pageURLs: $0.pageURLs)
        }
    }

    func page(for pageURL: URL) -> CachedDetailImagePage? {
        lock.lock()
        let key = pageURL.absoluteString
        guard let entry = storage[key] else {
            lock.unlock()
            return nil
        }
        if !entry.isPersistent, Date().timeIntervalSince(entry.updatedAt) > expirationInterval {
            storage[key] = nil
            rebuildCachedDetailPathsLocked()
            scheduleSaveLocked()
            lock.unlock()
            return nil
        }
        lock.unlock()
        return CachedDetailImagePage(pageURL: entry.pageURL, imageURLs: entry.imageURLs, pageURLs: entry.pageURLs)
    }

    func store(_ page: ResolvedImagePage) {
        store(pageURL: page.pageURL, imageURLs: page.imageURLs, pageURLs: page.pageURLs)
    }

    func store(pageURL: URL, imageURLs: [URL], pageURLs: [URL]) {
        lock.lock()
        let key = pageURL.absoluteString
        let existing = storage[key]
        let detailPath = pageURL.normalizedDetailPathKey
        storage[key] = Entry(
            pageURL: pageURL,
            imageURLs: imageURLs,
            pageURLs: pageURLs,
            updatedAt: Date(),
            isPersistent: persistentOverrides[detailPath] ?? existing?.isPersistent ?? false
        )
        cachedDetailPaths.insert(detailPath)
        pruneEntriesLocked()
        scheduleSaveLocked()
        lock.unlock()
    }

    func containsCachedPage(forDetailURL detailURL: URL) -> Bool {
        lock.lock()
        let hasEntry = cachedDetailPaths.contains(detailURL.normalizedDetailPathKey)
        lock.unlock()
        return hasEntry
    }

    func setPersistent(_ isPersistent: Bool, forDetailURL detailURL: URL) {
        lock.lock()
        persistentOverrides[detailURL.normalizedDetailPathKey] = isPersistent
        var didChange = false
        for (key, entry) in storage where entry.pageURL.isSameDetailPath(as: detailURL) && entry.isPersistent != isPersistent {
            var updated = entry
            updated.isPersistent = isPersistent
            updated.updatedAt = Date()
            storage[key] = updated
            didChange = true
        }
        if didChange {
            pruneEntriesLocked()
            scheduleSaveLocked()
        }
        lock.unlock()
    }

    func prune() {
        lock.lock()
        if pruneEntriesLocked() {
            scheduleSaveLocked()
        }
        lock.unlock()
    }

    func flush() {
        saveQueue.sync {}
        lock.lock()
        let snapshot = storage
        let cacheURL = cacheURL
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        lock.unlock()

        saveQueue.sync {
            Self.save(snapshot, to: cacheURL)
        }
    }

    func clear() throws {
        lock.lock()
        loadGeneration += 1
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        storage.removeAll()
        cachedDetailPaths.removeAll()
        let cacheDirectory = cacheURL.deletingLastPathComponent()
        lock.unlock()

        try saveQueue.sync {
            if FileManager.default.fileExists(atPath: cacheDirectory.path) {
                try FileManager.default.removeItem(at: cacheDirectory)
            }
        }
    }

    private func scheduleInitialLoad() {
        let cacheURL = cacheURL
        let generation = loadGeneration
        saveQueue.async { [weak self] in
            guard let data = try? Data(contentsOf: cacheURL),
                  let decoded = try? JSONDecoder().decode([String: Entry].self, from: data),
                  let self else {
                return
            }
            lock.lock()
            guard loadGeneration == generation else {
                lock.unlock()
                return
            }
            for (key, var entry) in decoded where storage[key] == nil {
                if let override = persistentOverrides[entry.pageURL.normalizedDetailPathKey] {
                    entry.isPersistent = override
                }
                storage[key] = entry
            }
            rebuildCachedDetailPathsLocked()
            if pruneEntriesLocked() {
                scheduleSaveLocked()
            }
            lock.unlock()
        }
    }

    @discardableResult
    private func pruneEntriesLocked() -> Bool {
        let now = Date()
        let originalKeys = Set(storage.keys)
        storage = storage.filter { _, entry in
            entry.isPersistent || now.timeIntervalSince(entry.updatedAt) <= expirationInterval
        }

        trimEntriesLocked(isPersistent: false, maxCount: maxVolatileEntryCount)
        trimEntriesLocked(isPersistent: true, maxCount: maxPersistentEntryCount)

        let didChange = Set(storage.keys) != originalKeys
        if didChange { rebuildCachedDetailPathsLocked() }
        return didChange
    }

    private func trimEntriesLocked(isPersistent: Bool, maxCount: Int) {
        let candidates = storage
            .filter { $0.value.isPersistent == isPersistent }
            .sorted { lhs, rhs in lhs.value.updatedAt > rhs.value.updatedAt }

        guard candidates.count > maxCount else { return }
        for (key, _) in candidates.dropFirst(maxCount) {
            storage[key] = nil
        }
    }

    private func rebuildCachedDetailPathsLocked() {
        cachedDetailPaths = Set(storage.values.map { $0.pageURL.normalizedDetailPathKey })
    }

    private func scheduleSaveLocked() {
        let snapshot = storage
        let cacheURL = cacheURL
        pendingSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            Self.save(snapshot, to: cacheURL)
        }
        pendingSaveWorkItem = workItem
        saveQueue.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private static func save(_ snapshot: [String: Entry], to cacheURL: URL) {
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            logger.error("Failed to save detail page cache: \(error.localizedDescription)")
        }
    }
}
