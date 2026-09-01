import Foundation

struct FavoriteDetailFact: Equatable {
    let label: String
    let value: String
}

struct FavoriteDetailMetadata: Equatable {
    let title: String
    let detailText: String
    let sourceTitle: String
    let sourceURL: URL
    let secondaryTitle: String?
    let secondaryURL: URL?
    let supportsDesktopWallpaper: Bool
    let facts: [FavoriteDetailFact]

    init(
        title: String,
        detailText: String,
        sourceTitle: String,
        sourceURL: URL,
        secondaryTitle: String?,
        secondaryURL: URL?,
        supportsDesktopWallpaper: Bool,
        facts: [FavoriteDetailFact] = []
    ) {
        self.title = title
        self.detailText = detailText
        self.sourceTitle = sourceTitle
        self.sourceURL = sourceURL
        self.secondaryTitle = secondaryTitle
        self.secondaryURL = secondaryURL
        self.supportsDesktopWallpaper = supportsDesktopWallpaper
        self.facts = facts
    }
}

/// A source-owned link that is safe only for an explicit user action. It is
/// presentation metadata, never an image request or redirect input.
struct FavoriteDetailExternalAction: Equatable {
    let title: String
    let url: URL
}

struct FavoriteResolvedImagePage {
    let imageURLs: [URL]
    let pageURLs: [URL]
    let recommendations: [OnlineGalleryRecommendation]
    let metadata: FavoriteDetailMetadata?
    let videoURL: URL?
    let externalAction: FavoriteDetailExternalAction?

    init(
        imageURLs: [URL],
        pageURLs: [URL],
        recommendations: [OnlineGalleryRecommendation] = [],
        metadata: FavoriteDetailMetadata? = nil,
        videoURL: URL? = nil,
        externalAction: FavoriteDetailExternalAction? = nil
    ) {
        self.imageURLs = imageURLs
        self.pageURLs = pageURLs
        self.recommendations = recommendations
        self.metadata = metadata
        self.videoURL = videoURL
        self.externalAction = externalAction
    }
}

/// Favorites only knows that a source can play and save an already resolved
/// video URL. Concrete player/downloader types remain owned by App assembly.
struct FavoriteVideoActions {
    let play: @MainActor (FavoriteRecord, URL) -> Void
    let saveAsMP4: @MainActor (FavoriteRecord, URL) -> Void
    /// 站点 HLS 若加密或无法无损封装，收藏详情仍可播放，但不得启用保存 MP4。
    let canSaveAsMP4: Bool

    init(
        play: @escaping @MainActor (FavoriteRecord, URL) -> Void,
        saveAsMP4: @escaping @MainActor (FavoriteRecord, URL) -> Void,
        canSaveAsMP4: Bool = true
    ) {
        self.play = play
        self.saveAsMP4 = saveAsMP4
        self.canSaveAsMP4 = canSaveAsMP4
    }
}

enum FavoriteDetailContent {
    case paged(pageURLs: [URL], estimatedImageCount: Int, pageImageCapacity: Int)
    case singleImage(URL?)
}

enum FavoriteDetailNavigationMode {
    case images
    case sourceRecords
}

struct FavoriteSourceAdapter {
    let source: FavoriteSource
    let detailContent: (FavoriteRecord) -> FavoriteDetailContent?
    let resolvePage: (URL) async throws -> FavoriteResolvedImagePage
    let configureImageRequest: (inout URLRequest) -> Void
    let detailMetadata: (FavoriteRecord) -> FavoriteDetailMetadata?
    let videoActions: FavoriteVideoActions?
    let navigationMode: FavoriteDetailNavigationMode
    let cachedExternalAction: (URL) -> FavoriteDetailExternalAction?

    init(
        source: FavoriteSource,
        detailContent: @escaping (FavoriteRecord) -> FavoriteDetailContent?,
        resolvePage: @escaping (URL) async throws -> FavoriteResolvedImagePage,
        configureImageRequest: @escaping (inout URLRequest) -> Void,
        detailMetadata: @escaping (FavoriteRecord) -> FavoriteDetailMetadata? = { _ in nil },
        videoActions: FavoriteVideoActions? = nil,
        navigationMode: FavoriteDetailNavigationMode = .images,
        cachedExternalAction: @escaping (URL) -> FavoriteDetailExternalAction? = { _ in nil }
    ) {
        self.source = source
        self.detailContent = detailContent
        self.resolvePage = resolvePage
        self.configureImageRequest = configureImageRequest
        self.detailMetadata = detailMetadata
        self.videoActions = videoActions
        self.navigationMode = navigationMode
        self.cachedExternalAction = cachedExternalAction
    }

    /// 木瓜视频 / 91PORNY / 糖心Vlog 这类纯视频收藏：列表双击播放，不打开详情栏。
    var playsFromFeed: Bool {
        videoActions != nil && navigationMode == .sourceRecords
    }

    func resolvePlayableVideoURL(for record: FavoriteRecord) async throws -> URL {
        guard let detailURL = URL(string: record.detailURL) else {
            throw FavoriteVideoResolveError.missingPlaylist
        }
        let page = try await resolvePage(detailURL)
        guard let videoURL = page.videoURL else {
            throw FavoriteVideoResolveError.missingPlaylist
        }
        return videoURL
    }
}

nonisolated enum FavoriteVideoResolveError: LocalizedError {
    case missingPlaylist

    var errorDescription: String? {
        switch self {
        case .missingPlaylist: "当前页面没有可播放地址"
        }
    }
}

/// Favorites owns only this source-neutral contract. Concrete online modules
/// register their adapters from App assembly, so removing a source module does
/// not leave imports or resolver/bridge references inside Favorites.
@MainActor
final class FavoriteSourceAdapterRegistry {
    static let shared = FavoriteSourceAdapterRegistry()

    private var adapters: [FavoriteSource: FavoriteSourceAdapter] = [:]

    private init() {}

    func replaceAdapters(_ adapters: [FavoriteSourceAdapter]) {
        self.adapters = Dictionary(uniqueKeysWithValues: adapters.map { ($0.source, $0) })
    }

    func adapter(for source: FavoriteSource) -> FavoriteSourceAdapter? {
        adapters[source]
    }

    func adapter(for record: FavoriteRecord) -> FavoriteSourceAdapter? {
        guard let source = FavoriteSource.source(for: record) else { return nil }
        return adapters[source]
    }
}
