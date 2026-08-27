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

    nonisolated static func wallpaperID(from detailURL: URL) -> String? {
        guard OnlineSourcePolicy.allows(detailURL, source: .wallhaven, resource: .html),
              let host = detailURL.host?.lowercased() else { return nil }
        let components = detailURL.pathComponents.filter { $0 != "/" }
        let candidate: String?
        switch host {
        case "wallhaven.cc", "www.wallhaven.cc":
            candidate = components.count == 2 && components[0] == "w" ? components[1] : nil
        case "whvn.cc":
            candidate = components.count == 1 ? components[0] : nil
        default:
            candidate = nil
        }
        guard let candidate, !candidate.isEmpty,
              candidate.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return candidate.lowercased()
    }

    nonisolated static func originalImageCandidates(for wallpaperID: String) -> [URL] {
        let normalizedID = wallpaperID.lowercased()
        guard normalizedID.count >= 2,
              normalizedID.allSatisfy({ $0.isLetter || $0.isNumber }) else { return [] }
        let bucket = String(normalizedID.prefix(2))
        return ["jpg", "png", "webp"].compactMap { fileExtension in
            URL(string: "https://w.wallhaven.cc/full/\(bucket)/wallhaven-\(normalizedID).\(fileExtension)")
        }.filter {
            OnlineSourcePolicy.allows($0, source: .wallhaven, resource: .media)
        }
    }

    private nonisolated static func toWallpaper(_ record: FavoriteRecord) -> Wallpaper? {
        guard let detailURL = URL(string: record.detailURL),
              OnlineSourcePolicy.allows(detailURL, source: .wallhaven, resource: .html) else {
            return nil
        }
        let coverURL = record.coverURL.flatMap(URL.init(string:))
            .flatMap { OnlineSourcePolicy.allows($0, source: .wallhaven, resource: .media) ? $0 : nil }
        let subtitleParts = record.subtitle.components(separatedBy: " · ")
        // 收藏记录的 subtitle 第三段保存的是 purity.title（见 record(from:)），反查恢复真实纯度。
        let purityText = subtitleParts.last
        let purity = WallhavenPurity.allCases.first { $0.title == purityText } ?? .sfw
        let resolutionText = subtitleParts.first.flatMap { $0.isEmpty ? nil : $0 } ?? "-"
        let fileType = subtitleParts.first { $0.lowercased().hasPrefix("image/") }
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
            resolutionText: resolutionText,
            fileSize: nil,
            fileType: fileType,
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
