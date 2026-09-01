import Foundation

nonisolated struct OnlineVideoTagLink: Hashable {
    let title: String
    let filter: String
}

nonisolated struct OnlineVideoItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let detailURL: URL
    let coverURL: URL?
    let coverAspectRatio: Double
    let durationText: String
    let authorName: String?
    let authorFilter: String?
    let tagFilters: [OnlineVideoTagLink]
    let opensFilter: String?

    var isDirectoryEntry: Bool {
        opensFilter != nil
    }

    init(
        id: String,
        title: String,
        subtitle: String,
        detailURL: URL,
        coverURL: URL?,
        coverAspectRatio: Double,
        durationText: String,
        authorName: String? = nil,
        authorFilter: String? = nil,
        tagFilters: [OnlineVideoTagLink] = [],
        opensFilter: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.detailURL = detailURL
        self.coverURL = coverURL
        self.coverAspectRatio = coverAspectRatio
        self.durationText = durationText
        self.authorName = authorName
        self.authorFilter = authorFilter
        self.tagFilters = tagFilters
        self.opensFilter = opensFilter
    }

    /// Grid card second line: author and duration when the list page had them.
    func gridCardMetadata(isFavorite: Bool) -> String {
        var parts: [String] = []
        let author = authorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !author.isEmpty { parts.append(author) }
        let duration = durationText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !duration.isEmpty { parts.append(duration) }
        if isFavorite { parts.append("已收藏") }
        return parts.joined(separator: " · ")
    }

    /// List row second line prefers a real author over the module placeholder.
    var listSecondaryLine: String {
        let author = authorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let leading = author.isEmpty ? subtitle : author
        let duration = durationText.trimmingCharacters(in: .whitespacesAndNewlines)
        return [leading, duration].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

nonisolated struct OnlineVideoListPage {
    let items: [OnlineVideoItem]
    let currentPage: Int
    let totalPages: Int
    let nextPageURL: URL?
}

nonisolated struct OnlineVideoResolvedDetail {
    let videoURL: URL
    let coverURL: URL?

    init(videoURL: URL, coverURL: URL? = nil) {
        self.videoURL = videoURL
        self.coverURL = coverURL
    }
}

enum OnlineVideoContentLayout: String {
    case list
    case grid
}

nonisolated enum OnlineVideoPlaybackError: LocalizedError {
    case notAVideo

    var errorDescription: String? {
        switch self {
        case .notAVideo: "这不是可播放的视频"
        }
    }
}
