import Foundation

extension AlbumDownloadSource {
    /// MissKon 图集下载源:逐页解析走 MissKonDetailResolver(cache-first
    /// 且自动写缓存),图片请求带 MissKon 的 Referer/User-Agent 头。
    static func missKon(_ item: MissKonItem) -> AlbumDownloadSource {
        AlbumDownloadSource(
            detailURL: item.detailURL,
            title: item.title,
            estimatedImageCount: item.imageCount,
            initialPageURLs: item.pageURLs,
            resolvePage: { pageURL in
                let page = try await MissKonDetailResolver.resolve(pageURL: pageURL)
                return AlbumResolvedPage(
                    pageURL: page.pageURL,
                    imageURLs: page.imageURLs,
                    pageURLs: page.pageURLs
                )
            },
            configureImageRequest: { request in
                MissKonRequestFactory.configureImageRequest(&request)
            }
        )
    }
}
