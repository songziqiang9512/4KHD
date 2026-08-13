import Foundation

extension AlbumDownloadSource {
    /// Gallery 图集下载源:逐页解析走 DetailPageHTMLResolver(cache-first
    /// 且自动写缓存),图片请求带 Gallery 的 Referer/User-Agent 头。
    static func gallery(_ item: GalleryItem) -> AlbumDownloadSource {
        AlbumDownloadSource(
            detailURL: item.detailURL,
            title: item.title,
            estimatedImageCount: item.imageCount,
            initialPageURLs: item.pageURLs,
            resolvePage: { pageURL in
                let page = try await DetailPageHTMLResolver.resolve(pageURL: pageURL)
                return AlbumResolvedPage(
                    pageURL: page.pageURL,
                    imageURLs: page.imageURLs,
                    pageURLs: page.pageURLs
                )
            },
            configureImageRequest: { request in
                GalleryRequestFactory.configureImageRequest(&request)
            }
        )
    }
}
