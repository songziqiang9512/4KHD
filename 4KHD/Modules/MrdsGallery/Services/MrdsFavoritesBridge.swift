import Foundation

enum MrdsFavoritesBridge {
    static func record(from item: MrdsGalleryItem, metadata: MrdsDetailMetadata?) -> FavoriteRecord {
        FavoriteRecord(
            id: "mrds:\(item.id)",
            sourceID: "mrds",
            title: item.title,
            rawTitle: item.rawTitle,
            subtitle: [item.category, item.metadataText, item.publishedDate]
                .filter { !$0.isEmpty }
                .joined(separator: " · "),
            detailURL: item.detailURL.absoluteString,
            coverURL: item.coverURL?.absoluteString,
            imageCount: metadata?.totalImages ?? 0,
            pageCount: 1
        )
    }

    static func item(from record: FavoriteRecord) -> MrdsGalleryItem? {
        guard let detailURL = URL(string: record.detailURL),
              OnlineSourcePolicy.allows(detailURL, source: .mrds, resource: .html),
              detailURL.path.range(of: #"^/archives/[0-9]+/?$"#, options: .regularExpression) != nil
        else {
            return nil
        }
        let coverURL = record.coverURL
            .flatMap(URL.init(string:))
            .flatMap { OnlineSourcePolicy.allows($0, source: .mrds, resource: .media) ? $0 : nil }
        return MrdsGalleryItem(
            id: detailURL.pathComponents.filter { $0 != "/" }.last ?? record.id,
            title: record.title,
            rawTitle: record.rawTitle,
            category: record.subtitle,
            publishedDate: "",
            detailURL: detailURL,
            coverURL: coverURL,
            coverAspectRatio: 1.6,
            hasVideo: false
        )
    }
}
