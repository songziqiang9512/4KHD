import Foundation

enum GalleryFavoritesBridge {
    nonisolated static func record(from item: GalleryItem) -> FavoriteRecord {
        FavoriteRecord(
            id: item.id,
            sourceID: item.section.rawValue,
            title: item.title,
            rawTitle: item.rawTitle,
            subtitle: item.subtitle,
            detailURL: item.detailURL.absoluteString,
            coverURL: item.coverURL?.absoluteString,
            imageCount: item.imageCount,
            pageCount: item.pageCount
        )
    }

    nonisolated static func galleryItems(from records: [FavoriteRecord]) -> [GalleryItem] {
        records.compactMap(toGalleryItem)
    }

    private nonisolated static func toGalleryItem(_ record: FavoriteRecord) -> GalleryItem? {
        guard let detailURL = URL(string: record.detailURL),
              isAllowedHost(detailURL.host) else {
            return nil
        }
        // Older snapshots stored module/source names instead of a section.
        // The host is authoritative for deciding whether this is a 4KHD item.
        let section = GallerySection(rawValue: record.sourceID) ?? .latest

        let coverURL = record.coverURL.flatMap(URL.init(string:))
        let pageURLs = pageURLs(detailURL: detailURL, pageCount: record.pageCount)
        return GalleryItem(
            id: record.id,
            section: section,
            kind: section == .popular ? .recommended : .gallery,
            title: record.title,
            rawTitle: record.rawTitle,
            subtitle: record.subtitle,
            detailURL: detailURL,
            coverURL: coverURL,
            coverAspectRatio: coverURL.flatMap(GalleryCoverAspectRatio.aspectRatio),
            imageCount: record.imageCount,
            pageCount: record.pageCount,
            pageURLs: pageURLs,
            sampleImageURLs: coverURL.map { [$0] } ?? []
        )
    }

    private nonisolated static func pageURLs(detailURL: URL, pageCount: Int) -> [URL] {
        let count = max(pageCount, 1)
        return (1...count).map { pageNumber in
            pageNumber == 1 ? detailURL : detailURL.appendingPathComponent("\(pageNumber)")
        }
    }

    private nonisolated static func isAllowedHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "4khd.com" || host.hasSuffix(".4khd.com")
    }
}
