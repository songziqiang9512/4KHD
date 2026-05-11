import Nuke
import SwiftUI

struct RemoteImageView<Placeholder: View>: View {
    let url: URL?
    let contentMode: ContentMode
    let priority: TaskPriority
    @ViewBuilder let placeholder: () -> Placeholder
    let onLoaded: () -> Void
    @State private var image: NSImage?
    @State private var loadedURL: URL?
    @State private var imageTask: ImageTask?

    init(
        url: URL?,
        contentMode: ContentMode,
        priority: TaskPriority = .utility,
        onLoaded: @escaping () -> Void = {},
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.contentMode = contentMode
        self.priority = priority
        self.onLoaded = onLoaded
        self.placeholder = placeholder
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url, priority: priority) {
            imageTask?.cancel()
            guard loadedURL != url else { return }
            loadedURL = url
            image = nil
            guard let url else { return }
            let request = RemoteImagePipeline.shared.request(for: url, priority: priority.nukePriority)
            imageTask = RemoteImagePipeline.shared.loadImage(with: request) { loadedImage in
                guard loadedURL == url else { return }
                image = loadedImage
                if loadedImage != nil {
                    onLoaded()
                }
            }
        }
        .onDisappear {
            imageTask?.cancel()
            imageTask = nil
        }
    }
}

final class RemoteImagePipeline {
    static let shared = RemoteImagePipeline()

    private let pipeline: ImagePipeline
    private let detailPrefetcher: ImagePrefetcher

    private init() {
        var configuration = ImagePipeline.Configuration()
        configuration.dataLoader = DataLoader(configuration: Self.urlSessionConfiguration)
        if let dataCache = try? DataCache(name: "com.songziqiang.4khd.images") {
            dataCache.sizeLimit = 1024 * 1024 * 1024
            configuration.dataCache = dataCache
        }
        configuration.dataCacheOptions.storedItems = [.originalImageData]
        configuration.isDeduplicationEnabled = true
        configuration.isRateLimiterEnabled = true
        configuration.dataLoadingQueue.maxConcurrentOperationCount = 6
        configuration.imageDecodingQueue.maxConcurrentOperationCount = 2
        let pipeline = ImagePipeline(configuration: configuration)
        self.pipeline = pipeline
        self.detailPrefetcher = ImagePrefetcher(
            pipeline: pipeline,
            destination: .memoryCache,
            maxConcurrentRequestCount: 3
        )
        self.detailPrefetcher.priority = .low
    }

    func request(for url: URL, priority: ImageRequest.Priority) -> ImageRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue("https://www.4khd.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

        return ImageRequest(urlRequest: request, priority: priority)
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
        guard !urls.isEmpty else { return }
        let requests = urls.map { request(for: $0, priority: .low) }
        detailPrefetcher.startPrefetching(with: requests)
    }

    func stopDetailPrefetching() {
        detailPrefetcher.stopPrefetching()
    }

    private static let urlSessionConfiguration: URLSessionConfiguration = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 128 * 1024 * 1024,
            diskCapacity: 1024 * 1024 * 1024,
            diskPath: "4KHDImageURLCache"
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 30
        configuration.httpMaximumConnectionsPerHost = 6
        return configuration
    }()
}

private extension TaskPriority {
    var nukePriority: ImageRequest.Priority {
        switch self {
        case .high, .userInitiated:
            .veryHigh
        case .medium:
            .high
        case .low, .utility:
            .normal
        case .background:
            .low
        default:
            .normal
        }
    }
}
