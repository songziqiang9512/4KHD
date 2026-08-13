import AppKit
import CryptoKit
import Foundation
import Nuke
import ImageIO

enum OnlineCacheLimit: String, CaseIterable, Identifiable {
    case mb512
    case gb1
    case gb2
    case gb4
    case unlimited

    static let defaultsKey = "com.songziqiang.4khd.onlineCacheLimit.v1"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mb512: "512 MB"
        case .gb1: "1 GB"
        case .gb2: "2 GB"
        case .gb4: "4 GB"
        case .unlimited: "无限制"
        }
    }

    var byteLimit: Int {
        switch self {
        case .mb512: 512 * 1024 * 1024
        case .gb1: 1024 * 1024 * 1024
        case .gb2: 2 * 1024 * 1024 * 1024
        case .gb4: 4 * 1024 * 1024 * 1024
        case .unlimited: Int.max
        }
    }

    static var current: OnlineCacheLimit {
        let rawValue = UserDefaults.standard.string(forKey: defaultsKey) ?? OnlineCacheLimit.gb1.rawValue
        return OnlineCacheLimit(rawValue: rawValue) ?? .gb1
    }

    static func apply(_ limit: OnlineCacheLimit) {
        UserDefaults.standard.set(limit.rawValue, forKey: defaultsKey)
        RemoteImagePipeline.shared.applyCacheLimit(limit)
    }
}

final class RemoteImagePipeline {
    static let shared = RemoteImagePipeline()

    private let pipeline: ImagePipeline
    private let detailPrefetcher: ImagePrefetcher
    private let thumbnailPrefetcher: ImagePrefetcher
    private let urlCache: URLCache
    private let dataCache: DataCache?
    private var inFlightTasks = Set<ImageTask>()

    private init() {
        let cacheLimit = OnlineCacheLimit.current.byteLimit
        let urlCache = Self.makeURLCache()
        var configuration = ImagePipeline.Configuration()
        configuration.dataLoader = DataLoader(configuration: Self.urlSessionConfiguration(urlCache: urlCache))
        configuration.imageCache = ImageCache(costLimit: 384 * 1024 * 1024, countLimit: 900)
        if let dataCache = try? DataCache(name: AppStorageFolders.imageCacheFolderName) {
            dataCache.sizeLimit = cacheLimit
            configuration.dataCache = dataCache
            dataCache.sweep()
            self.dataCache = dataCache
        } else {
            self.dataCache = nil
        }
        configuration.dataCachePolicy = .storeOriginalData
        configuration.isTaskCoalescingEnabled = true
        configuration.isRateLimiterEnabled = true
        configuration.dataLoadingQueue.maxConcurrentOperationCount = 6
        configuration.imageDecodingQueue.maxConcurrentOperationCount = 2
        let pipeline = ImagePipeline(configuration: configuration)
        self.pipeline = pipeline
        self.urlCache = urlCache
        self.detailPrefetcher = ImagePrefetcher(
            pipeline: pipeline,
            destination: .diskCache,
            maxConcurrentRequestCount: 3
        )
        self.detailPrefetcher.priority = .low
        self.thumbnailPrefetcher = ImagePrefetcher(
            pipeline: pipeline,
            destination: .diskCache,
            maxConcurrentRequestCount: 2
        )
        self.thumbnailPrefetcher.priority = .veryLow
    }

    func applyCacheLimit(_ limit: OnlineCacheLimit) {
        let bytes = limit.byteLimit
        dataCache?.sizeLimit = bytes
        dataCache?.sweep()
    }

    func clearAllCaches() {
        detailPrefetcher.stopPrefetching()
        thumbnailPrefetcher.stopPrefetching()
        inFlightTasks.forEach { $0.cancel() }
        inFlightTasks.removeAll()
        pipeline.cache.removeAll()
        urlCache.removeAllCachedResponses()
    }

    func request(
        for url: URL,
        priority: ImageRequest.Priority,
        maxPixelSize: CGFloat? = nil,
        configureURLRequest: ((inout URLRequest) -> Void)? = nil
    ) -> ImageRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .returnCacheDataElseLoad
        configureURLRequest?(&request)

        let processors: [ImageProcessing]
        if let maxPixelSize, maxPixelSize > 0 {
            // 宽度上限为主；高度上限为 2 倍宽度，防止超长图（长截图/超长壁纸）解码像素失控。
            // aspectFit 语义下普通竖图不受影响，只有高宽比超过 2:1 的图才会被高度封顶。
            processors = [
                ImageProcessors.Resize(
                    size: CGSize(width: maxPixelSize, height: maxPixelSize * 2),
                    unit: .pixels,
                    contentMode: .aspectFit,
                    upscale: false
                )
            ]
        } else {
            processors = []
        }

        return ImageRequest(urlRequest: request, processors: processors, priority: priority)
    }

    @discardableResult
    func loadImage(with request: ImageRequest, completion: @escaping (NSImage?) -> Void) -> ImageTask {
        let task = pipeline.loadImage(with: request) { [weak self] result in
            switch result {
            case .success(let response):
                completion(response.image)
                self?.pruneFinishedTasks()
            case .failure(let error):
                if self?.isRetriableLoadingError(error) == true {
                    // 瞬时网络错误自动重试一次，避免一次抖动让缩略图/详情图永久空白。
                    self?.retryLoadImageOnce(with: request, completion: completion)
                } else {
                    completion(nil)
                    self?.pruneFinishedTasks()
                }
            }
        }
        track(task)
        return task
    }

    private func retryLoadImageOnce(with request: ImageRequest, completion: @escaping (NSImage?) -> Void) {
        let task = pipeline.loadImage(with: request) { [weak self] result in
            switch result {
            case .success(let response):
                completion(response.image)
            case .failure:
                completion(nil)
            }
            self?.pruneFinishedTasks()
        }
        track(task)
    }

    private func isRetriableLoadingError(_ error: ImagePipeline.Error) -> Bool {
        guard case .dataLoadingFailed(let wrappedError) = error,
              let urlError = wrappedError as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    func cachedImage(with request: ImageRequest) -> NSImage? {
        pipeline.cache.cachedImage(for: request)?.image
    }

    func loadData(with request: ImageRequest, completion: @escaping (Data?) -> Void) -> ImageTask {
        let task = pipeline.loadData(with: request) { [weak self] result in
            switch result {
            case .success(let payload):
                completion(payload.data)
            case .failure:
                completion(nil)
            }
            self?.pruneFinishedTasks()
        }
        track(task)
        return task
    }

    func prefetchDetailImages(_ urls: [URL]) {
        let remoteURLs = urls.filter { !$0.isFileURL }
        guard !remoteURLs.isEmpty else { return }
        let requests = remoteURLs.map { request(for: $0, priority: .low) }
        detailPrefetcher.startPrefetching(with: requests)
    }

    func prefetchThumbnailImages(with requests: [ImageRequest]) {
        guard !requests.isEmpty else { return }
        thumbnailPrefetcher.startPrefetching(with: requests)
    }

    func stopDetailPrefetching() {
        detailPrefetcher.stopPrefetching()
    }

    private func track(_ task: ImageTask) {
        pruneFinishedTasks()
        inFlightTasks.insert(task)
    }

    private func pruneFinishedTasks() {
        inFlightTasks = inFlightTasks.filter { $0.state == .running }
    }

    private static func makeURLCache() -> URLCache {
        URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 0,
            diskPath: "4KHDImageURLCache"
        )
    }

    private static func urlSessionConfiguration(urlCache: URLCache) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = urlCache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 30
        configuration.httpMaximumConnectionsPerHost = 6
        return configuration
    }
}

actor LocalImageCache {
    struct FileVersion: Sendable {
        let fileSize: Int64?
        let modifiedAt: Date?
    }

    static let shared = LocalImageCache()

    private static let diskCacheDirectory: URL = {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = supportDirectory
            .appendingPathComponent("4KHD", isDirectory: true)
            .appendingPathComponent("LocalImageThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    nonisolated(unsafe) private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 700
        cache.totalCostLimit = 640 * 1024 * 1024
        return cache
    }()
    private var inFlight: [String: (id: UUID, task: Task<NSImage?, Never>)] = [:]
    private var failedSignatures = Set<String>()
    private var loadsSinceDiskPrune = 0
    private var didScheduleInitialDiskPrune = false
    private var cacheGeneration = 0
    private var isClearing = false
    private var clearWaiters: [CheckedContinuation<Void, Never>] = []

    private init() {}

    nonisolated func cachedImage(
        for url: URL,
        maxPixelSize: CGFloat?,
        fileVersion: FileVersion?
    ) -> NSImage? {
        guard let fileVersion else { return nil }
        let key = cacheKey(for: url, maxPixelSize: maxPixelSize, fileVersion: fileVersion)
        return Self.cache.object(forKey: key as NSString)
    }

    func image(
        for url: URL,
        maxPixelSize: CGFloat?,
        fileVersion: FileVersion? = nil
    ) async -> NSImage? {
        if isClearing {
            await withCheckedContinuation { continuation in
                clearWaiters.append(continuation)
            }
        }
        guard !Task.isCancelled else { return nil }
        scheduleDiskPruneIfNeeded()
        let resolvedVersion = fileVersion ?? self.fileVersion(for: url)
        let key = cacheKey(for: url, maxPixelSize: maxPixelSize, fileVersion: resolvedVersion)
        if let cached = Self.cache.object(forKey: key as NSString) {
            return cached
        }
        let signature = failureSignature(for: url, fileVersion: resolvedVersion)
        if failedSignatures.contains(signature) {
            return nil
        }
        if let inFlight = inFlight[key] {
            return await inFlight.task.value
        }

        let requestGeneration = cacheGeneration
        let requestID = UUID()
        let task = Task.detached(priority: .utility) { () -> NSImage? in
            if let diskImage = Self.diskImage(forKey: key) {
                return diskImage
            }
            guard let image = loadImage(at: url, maxPixelSize: maxPixelSize) else { return nil }
            guard !Task.isCancelled else { return nil }
            Self.writeToDisk(image, forKey: key)
            return image
        }
        inFlight[key] = (requestID, task)
        let loaded = await task.value
        if inFlight[key]?.id == requestID {
            inFlight[key] = nil
        }
        guard cacheGeneration == requestGeneration, !isClearing else { return nil }
        loadsSinceDiskPrune += 1

        if let loaded {
            failedSignatures.remove(signature)
            Self.cache.setObject(loaded, forKey: key as NSString, cost: loaded.cacheCost)
        } else {
            failedSignatures.insert(signature)
        }
        return loaded
    }

    func clear() async throws {
        if isClearing {
            await withCheckedContinuation { continuation in
                clearWaiters.append(continuation)
            }
            return
        }
        isClearing = true
        cacheGeneration += 1
        let activeTasks = inFlight.values.map(\.task)
        for task in activeTasks {
            task.cancel()
        }
        for task in activeTasks {
            _ = await task.value
        }
        inFlight.removeAll()
        failedSignatures.removeAll()
        loadsSinceDiskPrune = 0
        didScheduleInitialDiskPrune = false
        Self.cache.removeAllObjects()

        do {
            try await Task.detached(priority: .utility) {
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: Self.diskCacheDirectory.path) {
                    try fileManager.removeItem(at: Self.diskCacheDirectory)
                }
                try fileManager.createDirectory(
                    at: Self.diskCacheDirectory,
                    withIntermediateDirectories: true
                )
            }.value
            finishClearing()
        } catch {
            finishClearing()
            throw error
        }
    }

    private func scheduleDiskPruneIfNeeded() {
        let shouldPrune = !didScheduleInitialDiskPrune || loadsSinceDiskPrune >= 100
        guard shouldPrune else { return }
        didScheduleInitialDiskPrune = true
        loadsSinceDiskPrune = 0
        Task.detached(priority: .background) {
            Self.pruneDiskCache()
        }
    }

    private func finishClearing() {
        isClearing = false
        let waiters = clearWaiters
        clearWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private nonisolated func cacheKey(
        for url: URL,
        maxPixelSize: CGFloat?,
        fileVersion: FileVersion
    ) -> String {
        "\(url.path)#\(fileSignature(for: url, fileVersion: fileVersion))#\(Int(maxPixelSize ?? 0))"
    }

    private nonisolated func failureSignature(for url: URL, fileVersion: FileVersion) -> String {
        fileSignature(for: url, fileVersion: fileVersion)
    }

    private nonisolated func fileVersion(for url: URL) -> FileVersion {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return FileVersion(fileSize: nil, modifiedAt: nil)
        }
        return FileVersion(
            fileSize: (attributes[.size] as? NSNumber)?.int64Value,
            modifiedAt: attributes[.modificationDate] as? Date
        )
    }

    private nonisolated func fileSignature(for url: URL, fileVersion: FileVersion) -> String {
        let size = fileVersion.fileSize ?? -1
        let modifiedAt = fileVersion.modifiedAt?.timeIntervalSince1970 ?? 0
        return "\(url.path)|\(size)|\(Int64(modifiedAt))"
    }

    private nonisolated static func diskImage(forKey key: String) -> NSImage? {
        let url = diskCacheURL(forKey: key)
        guard let data = try? Data(contentsOf: url),
              let image = NSImage(data: data) else {
            return nil
        }
        return image
    }

    private nonisolated static func writeToDisk(_ image: NSImage, forKey key: String) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.86]) else { return }
        try? FileManager.default.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: diskCacheURL(forKey: key), options: .atomic)
    }

    private nonisolated static func pruneDiskCache() {
        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: diskCacheDirectory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let entries = urls.compactMap { url -> (url: URL, size: Int64, modifiedAt: Date)? in
            guard let values = try? url.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true else {
                return nil
            }
            return (
                url,
                Int64(values.fileSize ?? 0),
                values.contentModificationDate ?? .distantPast
            )
        }.sorted { $0.modifiedAt > $1.modifiedAt }

        let maxBytes: Int64 = 1024 * 1024 * 1024
        let maxFileCount = 20_000
        var retainedBytes: Int64 = 0
        var retainedCount = 0
        for entry in entries {
            if retainedCount >= maxFileCount || retainedBytes + entry.size > maxBytes {
                try? fileManager.removeItem(at: entry.url)
            } else {
                retainedBytes += entry.size
                retainedCount += 1
            }
        }
    }

    private nonisolated static func diskCacheURL(forKey key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return diskCacheDirectory.appendingPathComponent(hash).appendingPathExtension("jpg")
    }
}

nonisolated private func loadImage(at url: URL, maxPixelSize: CGFloat?) -> NSImage? {
    guard let maxPixelSize, maxPixelSize > 0 else {
        return NSImage(contentsOf: url)
    }

    let options: CFDictionary = [
        kCGImageSourceShouldCache: false
    ] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }

    let downsampleOptions: CFDictionary = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize)
    ] as CFDictionary

    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else { return nil }
    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
}

private extension NSImage {
    nonisolated var cacheCost: Int {
        guard let representation = representations.first else { return 1 }
        return max(representation.pixelsWide * representation.pixelsHigh * 4, 1)
    }
}
