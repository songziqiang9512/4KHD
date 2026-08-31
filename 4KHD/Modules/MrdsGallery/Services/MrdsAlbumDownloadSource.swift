import Foundation

extension AlbumDownloadSource {
    @MainActor
    static func mrds(_ item: MrdsGalleryItem) -> AlbumDownloadSource {
        AlbumDownloadSource(
            detailURL: item.detailURL,
            title: item.title,
            estimatedImageCount: max(item.hasVideo ? 0 : 1, 1),
            initialPageURLs: [item.detailURL],
            resolvePage: { pageURL in
                let page = try await MrdsDetailResolver.resolve(pageURL: pageURL)
                return AlbumResolvedPage(
                    pageURL: page.pageURL,
                    imageURLs: page.imageURLs,
                    pageURLs: page.pageURLs
                )
            },
            configureImageRequest: MrdsRequestFactory.configureImageRequest
        )
    }
}
