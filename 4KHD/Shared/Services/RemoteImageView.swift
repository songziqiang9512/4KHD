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
    /// 失败 URL 短期负缓存：坏图链接在快速滚动时每次滚入都会重新请求，
    /// 记录 60s 内直接跳过，避免反复占用并发配额。只作用于缩略图级
    /// （≤ .normal）请求，详情图（.high/.veryHigh）的显式重试不受影响。
    private var failedURLs: [URL: Date] = [:]
    private let negativeCacheWindow: TimeInterval = 60

    private init() {
        let cacheLimit = OnlineCacheLimit.current.byteLimit
        let urlCache = Self.makeURLCache()
        var configuration = ImagePipeline.Configuration()
        configuration.dataLoader = DataLoader(configuration: Self.urlSessionConfiguration(urlCache: urlCache))
        configuration.imageCache = ImageCache(costLimit: 288 * 1024 * 1024, countLimit: 700)
        if let dataCache = try? DataCache(name: AppStorageFolders.imageCacheFolderName) {
            dataCache.sizeLimit = cacheLimit
            configuration.dataCache = dataCache
            self.dataCache = dataCache
            // sweep 是同步磁盘遍历；放到后台，避免首次访问 shared（启动路径）时主线程卡顿。
            DispatchQueue.global(qos: .utility).async {
                dataCache.sweep()
            }
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
        // 清理放后台，改上限时 UI 不卡。
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.dataCache?.sweep()
        }
    }

    func clearAllCaches() {
        detailPrefetcher.stopPrefetching()
        thumbnailPrefetcher.stopPrefetching()
        inFlightTasks.forEach { $0.cancel() }
        inFlightTasks.removeAll()
        pipeline.cache.removeAll()
        failedURLs.removeAll()
        urlCache.removeAllCachedResponses()
        // DataCache 磁盘层的 removeAll 是同步遍历删除,放后台避免卡主线程。
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.dataCache?.removeAll()
        }
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
    func loadImage(with request: ImageRequest, completion: @escaping (NSImage?) -> Void) -> ImageTask? {
        if isNegativeCacheEligible(request), let url = request.url, let failedAt = failedURLs[url],
           Date().timeIntervalSince(failedAt) < negativeCacheWindow {
            completion(nil)
            return nil
        }
        let task = pipeline.loadImage(with: request) { [weak self] result in
            switch result {
            case .success(let response):
                completion(response.image)
                self?.pruneFinishedTasks()
            case .failure(let error):
                if let url = request.url, self?.isNegativeCacheEligible(request) == true {
                    self?.recordFailure(for: url)
                }
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

    /// 负缓存仅适用于缩略图/网格级请求（≤ .normal）：滚动复用场景下坏链接
    /// 值得短期跳过；详情图（.high/.veryHigh）失败会留给用户显式重试。
    private func isNegativeCacheEligible(_ request: ImageRequest) -> Bool {
        switch request.priority {
        case .veryLow, .low, .normal: true
        case .high, .veryHigh: false
        }
    }

    private func recordFailure(for url: URL) {
        failedURLs[url] = Date()
        // 顺带清理过期条目，防止字典无界增长。
        if failedURLs.count > 100 {
            let cutoff = Date().addingTimeInterval(-negativeCacheWindow)
            failedURLs = failedURLs.filter { $0.value > cutoff }
        }
    }

    private func retryLoadImageOnce(with request: ImageRequest, completion: @escaping (NSImage?) -> Void) {
        // 短退避 1s 再重试：瞬时网络抖动时避免所有在途请求同时失败、同时重试的请求风暴。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else {
                completion(nil)
                return
            }
            let task = self.pipeline.loadImage(with: request) { [weak self] result in
                switch result {
                case .success(let response):
                    completion(response.image)
                case .failure:
                    if let url = request.url, self?.isNegativeCacheEligible(request) == true {
                        self?.recordFailure(for: url)
                    }
                    completion(nil)
                }
                self?.pruneFinishedTasks()
            }
            self.track(task)
        }
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
        cache.countLimit = 500
        cache.totalCostLimit = 384 * 1024 * 1024
        return cache
    }()
    /// 本地图解码并发上限：冷启动浏览大库时几十个 cell 同时解码会打满 CPU，
    /// 限流到 3 路让缩略图分批出图（与 Nuke 侧 2 路解码队列同理）。
    private static let decodeSemaphore = DispatchSemaphore(value: 3)
    private var inFlight: [String: (id: UUID, task: Task<NSImage?, Never>)] = [:]
    /// 文件版本短期缓存：连续请求同一批 URL 时避免每个 cell 都同步 stat 一次。
    /// 30s TTL：文件被导入/覆盖后最迟 30s 重取版本，否则缓存键用旧版本
    /// 会把新文件内容当成旧文件命中（详情图短暂显示旧内容）。
    /// prune 周期兜底清空，防止异常路径下条目滞留。
    private var fileVersionCache: [String: (version: FileVersion, cachedAt: Date)] = [:]
    private let fileVersionTTL: TimeInterval = 30
    private var failedSignatures = Set<String>()
    /// 失效签名无界增长会拖垮大库浏览(外接盘断开后整库失效);
    /// 超限整体清空,允许失败项周期性重试。
    private let maxFailedSignatureCount = 4000
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
            // 信号量等待是同步操作，不能在 async 闭包里直接做，包进同步函数；
            // 限流覆盖读盘 + 解码（CPU 密集段），写盘放外部，取消语义保持原样。
            guard let image = Self.loadFromDiskOrDecode(key: key, url: url, maxPixelSize: maxPixelSize) else {
                return nil
            }
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
            if failedSignatures.count > maxFailedSignatureCount {
                failedSignatures.removeAll()
            }
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
        fileVersionCache.removeAll()
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
        // 与文件版本缓存同周期失效：文件可能被导入/覆盖，版本缓存不能无限期存活。
        fileVersionCache.removeAll()
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

    private func fileVersion(for url: URL) -> FileVersion {
        if let entry = fileVersionCache[url.path],
           Date().timeIntervalSince(entry.cachedAt) < fileVersionTTL {
            return entry.version
        }
        let version = statFileVersion(for: url)
        fileVersionCache[url.path] = (version, Date())
        return version
    }

    private nonisolated func statFileVersion(for url: URL) -> FileVersion {
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

    /// 信号量限流的磁盘读 + 解码（同步函数，供 detached 任务调用）。
    private nonisolated static func loadFromDiskOrDecode(key: String, url: URL, maxPixelSize: CGFloat?) -> NSImage? {
        decodeSemaphore.wait()
        defer { decodeSemaphore.signal() }
        if let diskImage = diskImage(forKey: key) {
            return diskImage
        }
        return loadImage(at: url, maxPixelSize: maxPixelSize)
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
        try? FileManager.default.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
        let url = diskCacheURL(forKey: key)
        // CGImageDestination 直接编码到文件，比 NSBitmapImageRep + Data.write 少一次完整
        // 位图到内存数据的往返，编码更快。先写临时文件再原子替换：
        // 中断/崩溃不会留下半截损坏的缓存文件（读侧对损坏文件的处理是重新解码，
        // 但损坏文件不清理会反复触发解码，浪费解码配额）。
        let temporaryURL = diskCacheDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("tmp")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        guard let destination = CGImageDestinationCreateWithURL(temporaryURL as CFURL, "public.jpeg" as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(
            destination,
            cgImage,
            [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return }
        try? FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
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
