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
        guard let section = GallerySection(rawValue: record.sourceID),
              section != .favorites,
              let detailURL = URL(string: record.detailURL),
              detailURL.host?.contains("4khd.com") == true else {
            return nil
        }

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
}
