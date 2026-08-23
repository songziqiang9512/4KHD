import Foundation

/// A source-neutral related gallery card extracted from an online detail page.
/// Site-specific modules remain responsible for turning it into their own item model.
nonisolated struct OnlineGalleryRecommendation: Identifiable, Codable, Hashable, Sendable {
    let title: String
    let detailURL: URL
    let coverURL: URL?
    let coverAspectRatio: Double?
    let imageCount: Int?

    var id: String { detailURL.absoluteString }
}
