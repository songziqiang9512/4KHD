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
              OnlineSourcePolicy.allows(detailURL, source: .wallhaven, resource: .html) else {
            return nil
        }
        let coverURL = record.coverURL.flatMap(URL.init(string:))
            .flatMap { OnlineSourcePolicy.allows($0, source: .wallhaven, resource: .media) ? $0 : nil }
        // 收藏记录的 subtitle 第三段保存的是 purity.title（见 record(from:)），反查恢复真实纯度。
        let purityText = record.subtitle.components(separatedBy: " · ").last
        let purity = WallhavenPurity.allCases.first { $0.title == purityText } ?? .sfw
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
            purity: purity,
            category: nil,
            views: nil,
            favorites: nil,
            uploader: nil
        )
    }
}
