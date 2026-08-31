import Foundation

nonisolated struct OnlineVideoItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let detailURL: URL
    let coverURL: URL?
    let coverAspectRatio: Double
    let durationText: String
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
