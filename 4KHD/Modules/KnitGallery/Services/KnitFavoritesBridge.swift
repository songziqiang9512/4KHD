import Foundation

enum KnitFavoritesBridge {
    static func record(from item: KnitGalleryItem, metadata: KnitDetailMetadata?) -> FavoriteRecord {
        FavoriteRecord(
            id: "knit:\(item.id)",
            sourceID: "knit",
            title: item.title,
            rawTitle: item.rawTitle,
            subtitle: [item.category, item.metadataText].filter { !$0.isEmpty }.joined(separator: " · "),
            detailURL: item.detailURL.absoluteString,
            coverURL: item.coverURL?.absoluteString,
            imageCount: metadata?.totalImages ?? item.estimatedImageCount,
            pageCount: metadata?.totalPages ?? max(Int(ceil(Double(item.estimatedImageCount) / 10.0)), 1)
        )
    }

    static func item(from record: FavoriteRecord) -> KnitGalleryItem? {
        guard let detailURL = URL(string: record.detailURL),
              OnlineSourcePolicy.allows(detailURL, source: .knit, resource: .html),
              detailURL.path.range(of: #"^/article/[0-9]+/?$"#, options: .regularExpression) != nil else {
            return nil
        }
        let coverURL = record.coverURL
            .flatMap(URL.init(string:))
            .flatMap { OnlineSourcePolicy.allows($0, source: .knit, resource: .media) ? $0 : nil }
        return KnitGalleryItem(
            id: detailURL.pathComponents.filter { $0 != "/" }.last ?? record.id,
            title: record.title,
            rawTitle: record.rawTitle,
            category: record.subtitle,
            publishedDate: "",
            viewCount: nil,
            detailURL: detailURL,
            coverURL: coverURL,
            coverAspectRatio: 1.5,
            reportedPhotoCount: record.imageCount,
            reportedGIFCount: 0,
            reportedVideoCount: 0
        )
    }
}
