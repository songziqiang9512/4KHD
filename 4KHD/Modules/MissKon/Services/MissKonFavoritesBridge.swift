import Foundation

enum MissKonFavoritesBridge {
    nonisolated static func record(from item: MissKonItem) -> FavoriteRecord {
        FavoriteRecord(
            id: item.id,
            sourceID: item.section.rawValue,
            title: item.title,
            rawTitle: item.title,
            subtitle: item.tags.joined(separator: ", "),
            detailURL: item.detailURL.absoluteString,
            coverURL: item.coverURL?.absoluteString,
            imageCount: item.imageCount,
            pageCount: item.pageCount
        )
    }

    nonisolated static func missKonItems(from records: [FavoriteRecord]) -> [MissKonItem] {
        records.compactMap(toMissKonItem)
    }

    private nonisolated static func toMissKonItem(_ record: FavoriteRecord) -> MissKonItem? {
        guard let section = MissKonSection(rawValue: record.sourceID),
              section != .favorites,
              let detailURL = URL(string: record.detailURL) else {
            return nil
        }

        let coverURL = record.coverURL.flatMap(URL.init(string:))
        let pageURLs = pageURLs(detailURL: detailURL, pageCount: record.pageCount)
        return MissKonItem(
            id: record.id,
            section: section,
            title: record.title,
            detailURL: detailURL,
            coverURL: coverURL,
            coverAspectRatio: nil,
            imageCount: record.imageCount,
            pageCount: record.pageCount,
            pageURLs: pageURLs,
            tags: record.subtitle.isEmpty ? [] : record.subtitle.components(separatedBy: ", ")
        )
    }

    private nonisolated static func pageURLs(detailURL: URL, pageCount: Int) -> [URL] {
        let count = max(pageCount, 1)
        return (1...count).map { pageNumber in
            pageNumber == 1 ? detailURL : detailURL.appendingPathComponent("\(pageNumber)")
        }
    }
}
