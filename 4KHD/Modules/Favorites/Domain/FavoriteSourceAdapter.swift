import Foundation

struct FavoriteDetailMetadata: Equatable {
    let title: String
    let detailText: String
    let sourceTitle: String
    let sourceURL: URL
    let secondaryTitle: String?
    let secondaryURL: URL?
    let supportsDesktopWallpaper: Bool
}

struct FavoriteResolvedImagePage {
    let imageURLs: [URL]
    let pageURLs: [URL]
    let recommendations: [OnlineGalleryRecommendation]
    let metadata: FavoriteDetailMetadata?

    init(
        imageURLs: [URL],
        pageURLs: [URL],
        recommendations: [OnlineGalleryRecommendation] = [],
        metadata: FavoriteDetailMetadata? = nil
    ) {
        self.imageURLs = imageURLs
        self.pageURLs = pageURLs
        self.recommendations = recommendations
        self.metadata = metadata
    }
}

enum FavoriteDetailContent {
    case paged(pageURLs: [URL], estimatedImageCount: Int)
    case singleImage(URL?)
}

struct FavoriteSourceAdapter {
    let source: FavoriteSource
    let detailContent: (FavoriteRecord) -> FavoriteDetailContent?
    let resolvePage: (URL) async throws -> FavoriteResolvedImagePage
    let configureImageRequest: (inout URLRequest) -> Void
    let detailMetadata: (FavoriteRecord) -> FavoriteDetailMetadata?

    init(
        source: FavoriteSource,
        detailContent: @escaping (FavoriteRecord) -> FavoriteDetailContent?,
        resolvePage: @escaping (URL) async throws -> FavoriteResolvedImagePage,
        configureImageRequest: @escaping (inout URLRequest) -> Void,
        detailMetadata: @escaping (FavoriteRecord) -> FavoriteDetailMetadata? = { _ in nil }
    ) {
        self.source = source
        self.detailContent = detailContent
        self.resolvePage = resolvePage
        self.configureImageRequest = configureImageRequest
        self.detailMetadata = detailMetadata
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
