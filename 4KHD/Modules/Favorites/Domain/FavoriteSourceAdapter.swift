import Foundation

struct FavoriteResolvedImagePage {
    let imageURLs: [URL]
    let pageURLs: [URL]
    let recommendations: [OnlineGalleryRecommendation]

    init(
        imageURLs: [URL],
        pageURLs: [URL],
        recommendations: [OnlineGalleryRecommendation] = []
    ) {
        self.imageURLs = imageURLs
        self.pageURLs = pageURLs
        self.recommendations = recommendations
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
