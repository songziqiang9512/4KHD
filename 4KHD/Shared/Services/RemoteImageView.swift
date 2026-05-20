import AppKit
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
        NotificationCenter.default.post(name: didChangeNotification, object: limit)
    }

    static let didChangeNotification = Notification.Name("OnlineCacheLimitDidChangeNotification")
}

final class RemoteImagePipeline {
    static let shared = RemoteImagePipeline()

    private let pipeline: ImagePipeline
    private let detailPrefetcher: ImagePrefetcher
    private let urlCache: URLCache
    private let dataCache: DataCache?

    private init() {
        let cacheLimit = OnlineCacheLimit.current.byteLimit
        let urlCache = Self.makeURLCache(diskCapacity: cacheLimit)
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
        configuration.dataCacheOptions.storedItems = [.originalImageData]
        configuration.isDeduplicationEnabled = true
        configuration.isRateLimiterEnabled = true
        configuration.dataLoadingQueue.maxConcurrentOperationCount = 6
        configuration.imageDecodingQueue.maxConcurrentOperationCount = 2
        let pipeline = ImagePipeline(configuration: configuration)
        self.pipeline = pipeline
        self.urlCache = urlCache
        self.detailPrefetcher = ImagePrefetcher(
            pipeline: pipeline,
            destination: .memoryCache,
            maxConcurrentRequestCount: 3
        )
        self.detailPrefetcher.priority = .low
    }

    func applyCacheLimit(_ limit: OnlineCacheLimit) {
        let bytes = limit.byteLimit
        dataCache?.sizeLimit = bytes
        dataCache?.sweep()
        urlCache.diskCapacity = bytes
        urlCache.memoryCapacity = min(bytes / 4, 128 * 1024 * 1024)
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
            processors = [ImageProcessors.Resize(width: maxPixelSize, unit: .pixels, upscale: false)]
        } else {
            processors = []
        }

        return ImageRequest(urlRequest: request, processors: processors, priority: priority)
    }

    @discardableResult
    func loadImage(with request: ImageRequest, completion: @escaping (NSImage?) -> Void) -> ImageTask {
        pipeline.loadImage(with: request) { result in
            switch result {
            case .success(let response):
                completion(response.image)
            case .failure:
                completion(nil)
            }
        }
    }

    func loadData(with request: ImageRequest, completion: @escaping (Data?) -> Void) -> ImageTask {
        pipeline.loadData(with: request) { result in
            switch result {
            case .success(let payload):
                completion(payload.data)
            case .failure:
                completion(nil)
            }
        }
    }

    func prefetchDetailImages(_ urls: [URL]) {
        let remoteURLs = urls.filter { !$0.isFileURL }
        guard !remoteURLs.isEmpty else { return }
        let requests = remoteURLs.map { request(for: $0, priority: .low) }
        detailPrefetcher.startPrefetching(with: requests)
    }

    func stopDetailPrefetching() {
        detailPrefetcher.stopPrefetching()
    }

    private static func makeURLCache(diskCapacity: Int) -> URLCache {
        URLCache(
            memoryCapacity: min(diskCapacity / 4, 128 * 1024 * 1024),
            diskCapacity: diskCapacity,
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
    static let shared = LocalImageCache()

    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 700
        cache.totalCostLimit = 640 * 1024 * 1024
        return cache
    }()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private var failedSignatures = Set<String>()

    private init() {}

    nonisolated func cachedImage(for url: URL, maxPixelSize: CGFloat?) -> NSImage? {
        Self.cache.object(forKey: cacheKey(for: url, maxPixelSize: maxPixelSize) as NSString)
    }

    func image(for url: URL, maxPixelSize: CGFloat?) async -> NSImage? {
        let key = cacheKey(for: url, maxPixelSize: maxPixelSize)
        if let cached = Self.cache.object(forKey: key as NSString) {
            return cached
        }
        let signature = failureSignature(for: url)
        if let signature, failedSignatures.contains(signature) {
            return nil
        }
        if let task = inFlight[key] {
            return await task.value
        }

        let task = Task.detached(priority: .utility) {
            loadImage(at: url, maxPixelSize: maxPixelSize)
        }
        inFlight[key] = task
        let loaded = await task.value
        inFlight[key] = nil

        if let loaded {
            if let signature { failedSignatures.remove(signature) }
            Self.cache.setObject(loaded, forKey: key as NSString, cost: loaded.cacheCost)
        } else if let signature {
            failedSignatures.insert(signature)
        }
        return loaded
    }

    private nonisolated func cacheKey(for url: URL, maxPixelSize: CGFloat?) -> String {
        "\(url.path)#\(Int(maxPixelSize ?? 0))"
    }

    private nonisolated func failureSignature(for url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(url.path)|\(size)|\(Int64(modifiedAt))"
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
