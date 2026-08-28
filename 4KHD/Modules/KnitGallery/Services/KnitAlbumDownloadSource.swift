import Foundation

extension AlbumDownloadSource {
    @MainActor
    static func knit(_ item: KnitGalleryItem) -> AlbumDownloadSource {
        AlbumDownloadSource(
            detailURL: item.detailURL,
            title: item.title,
            estimatedImageCount: item.estimatedImageCount,
            initialPageURLs: [item.detailURL],
            resolvePage: { pageURL in
                let page = try await KnitDetailResolver.resolve(pageURL: pageURL)
                return AlbumResolvedPage(
                    pageURL: page.pageURL,
                    imageURLs: page.imageURLs,
                    pageURLs: page.pageURLs
                )
            },
            configureImageRequest: KnitRequestFactory.configureImageRequest
        )
    }
}
