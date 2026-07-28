import Foundation

struct FavoriteRecord: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let sourceID: String
    let title: String
    let rawTitle: String
    let subtitle: String
    let detailURL: String
    let coverURL: String?
    let imageCount: Int
    let pageCount: Int
}
