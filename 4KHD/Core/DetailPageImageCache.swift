import Foundation

final class DetailPageImageCache {
    static let shared = DetailPageImageCache()

    private struct Entry: Codable {
        let pageURL: URL
        let imageURLs: [URL]
        let pageURLs: [URL]
        var updatedAt: Date
        var isPersistent: Bool
    }

    private let lock = NSLock()
    private let cacheURL: URL
    private let expirationInterval: TimeInterval = 7 * 24 * 60 * 60
    private var storage: [String: Entry] = [:]
    private var cachedDetailPaths = Set<String>()
    private var didLoadFromDisk = false

    private init() {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = supportDirectory.appendingPathComponent("4KHD/DetailPageCache", isDirectory: true)
        cacheURL = directory.appendingPathComponent("pages.json")
    }

    func urls(for pageURL: URL) -> ResolvedImagePage? {
        lock.lock()
        loadFromDiskIfNeededLocked()
        let key = pageURL.absoluteString
        guard let entry = storage[key] else {
            lock.unlock()
            return nil
        }
        if !entry.isPersistent, Date().timeIntervalSince(entry.updatedAt) > expirationInterval {
            storage[key] = nil
            cachedDetailPaths.remove(entry.pageURL.normalizedDetailPathKey)
            saveToDiskLocked()
            lock.unlock()
            return nil
        }
        lock.unlock()
        return ResolvedImagePage(pageURL: entry.pageURL, imageURLs: entry.imageURLs, pageURLs: entry.pageURLs)
    }

    func store(_ page: ResolvedImagePage) {
        lock.lock()
        loadFromDiskIfNeededLocked()
        let key = page.pageURL.absoluteString
        let existing = storage[key]
        storage[key] = Entry(
            pageURL: page.pageURL,
            imageURLs: page.imageURLs,
            pageURLs: page.pageURLs,
            updatedAt: Date(),
            isPersistent: existing?.isPersistent ?? false
        )
        cachedDetailPaths.insert(page.pageURL.normalizedDetailPathKey)
        saveToDiskLocked()
        lock.unlock()
    }

    func containsCachedPage(forDetailURL detailURL: URL) -> Bool {
        lock.lock()
        loadFromDiskIfNeededLocked()
        let hasEntry = cachedDetailPaths.contains(detailURL.normalizedDetailPathKey)
        lock.unlock()
        return hasEntry
    }

    func setPersistent(_ isPersistent: Bool, forDetailURL detailURL: URL) {
        lock.lock()
        loadFromDiskIfNeededLocked()
        var didChange = false
        for (key, entry) in storage where entry.pageURL.isSameDetailPath(as: detailURL) && entry.isPersistent != isPersistent {
            var updated = entry
            updated.isPersistent = isPersistent
            updated.updatedAt = Date()
            storage[key] = updated
            didChange = true
        }
        if didChange {
            saveToDiskLocked()
        }
        lock.unlock()
    }

    private func loadFromDiskIfNeededLocked() {
        guard !didLoadFromDisk else { return }
        didLoadFromDisk = true
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            storage = [:]
            cachedDetailPaths = []
            return
        }
        storage = decoded
        rebuildCachedDetailPathsLocked()
        pruneExpiredEntriesLocked()
    }

    private func pruneExpiredEntriesLocked() {
        let now = Date()
        let originalCount = storage.count
        storage = storage.filter { _, entry in
            entry.isPersistent || now.timeIntervalSince(entry.updatedAt) <= expirationInterval
        }
        if storage.count != originalCount {
            rebuildCachedDetailPathsLocked()
            saveToDiskLocked()
        }
    }

    private func rebuildCachedDetailPathsLocked() {
        cachedDetailPaths = Set(storage.values.map { $0.pageURL.normalizedDetailPathKey })
    }

    private func saveToDiskLocked() {
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(storage)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
        }
    }
}
