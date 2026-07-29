import Foundation

enum WallhavenFavoritesBridge {
    static func record(from wallpaper: Wallpaper) -> FavoriteRecord {
        FavoriteRecord(
            id: wallpaper.id,
            sourceID: "wallhaven",
            title: wallpaper.displayName,
            rawTitle: wallpaper.id,
            subtitle: [
                wallpaper.resolutionText,
                wallpaper.fileType ?? "",
                wallpaper.purity.title
            ].filter { !$0.isEmpty }.joined(separator: " · "),
            detailURL: wallpaper.sourcePageUrl.absoluteString,
            coverURL: wallpaper.previewUrl?.absoluteString ?? wallpaper.thumbnailUrl?.absoluteString,
            imageCount: 1,
            pageCount: 1
        )
    }

    nonisolated static func wallpapers(from records: [FavoriteRecord]) -> [Wallpaper] {
        records.compactMap(toWallpaper)
    }

    private nonisolated static func toWallpaper(_ record: FavoriteRecord) -> Wallpaper? {
        guard let detailURL = URL(string: record.detailURL),
              isAllowedHost(detailURL.host) else {
            return nil
        }
        let coverURL = record.coverURL.flatMap(URL.init(string:))
        return Wallpaper(
            id: record.id,
            displayName: record.title,
            source: .wallhaven,
            sourcePageUrl: detailURL,
            sourceUrl: nil,
            thumbnailUrl: coverURL,
            previewUrl: coverURL,
            fullImageUrl: nil,
            width: nil,
            height: nil,
            resolutionText: "-",
            fileSize: nil,
            fileType: nil,
            colors: [],
            tags: [],
            createdAt: nil,
            purity: .sfw,
            category: nil,
            views: nil,
            favorites: nil,
            uploader: nil
        )
    }

    private nonisolated static func isAllowedHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "wallhaven.cc" || host == "whvn.cc" || host.hasSuffix(".wallhaven.cc")
    }
}
