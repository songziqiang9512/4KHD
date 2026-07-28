import Foundation

final class ApifyLibrary {
    private struct RootPayload: Decodable {
        let sections: [String: SectionPayload]
    }

    private struct SectionPayload: Decodable {
        let items: [ItemPayload]
    }

    private struct ItemPayload: Decodable {
        let id: String
        let displayTitle: String?
        let rawTitle: String?
        let subtitle: String?
        let detailURL: String?
        let coverURL: String?
        let imageCount: Int?
        let pageCount: Int?
        let pageURLs: [String]?
        let sampleImageURLs: [String]?
    }

    private var itemsBySection: [GallerySection: [GalleryItem]]

    init(bundle: Bundle = .main) {
        let payload = Self.loadPayload(bundle: bundle)
        itemsBySection = Self.mapPayload(payload)
    }

    private init(itemsBySection: [GallerySection: [GalleryItem]]) {
        self.itemsBySection = itemsBySection
    }

    func items(in section: GallerySection) -> [GalleryItem] {
        itemsBySection[section] ?? []
    }

    func replacing(section: GallerySection, with items: [GalleryItem]) -> ApifyLibrary {
        var updatedItemsBySection = itemsBySection
        updatedItemsBySection[section] = items
        return ApifyLibrary(itemsBySection: updatedItemsBySection)
    }

    func appending(section: GallerySection, items: [GalleryItem]) -> ApifyLibrary {
        var updatedItemsBySection = itemsBySection
        var existingItems = updatedItemsBySection[section] ?? []
        var existingIDs = Set(existingItems.map(\.id))
        for item in items where existingIDs.insert(item.id).inserted {
            existingItems.append(item)
        }
        updatedItemsBySection[section] = existingItems
        return ApifyLibrary(itemsBySection: updatedItemsBySection)
    }

    private static func loadPayload(bundle: Bundle) -> RootPayload? {
        guard let url = bundle.url(forResource: "expanded-ui-content", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(RootPayload.self, from: data)
    }

    private static func mapPayload(_ payload: RootPayload?) -> [GallerySection: [GalleryItem]] {
        var mapped: [GallerySection: [GalleryItem]] = [:]
        for section in GallerySection.allCases where section.isNetworkBacked {
            let rawItems = payload?.sections[section.rawValue]?.items ?? []
            mapped[section] = rawItems.compactMap { Self.makeItem($0, section: section) }
        }
        return mapped
    }

    private static func makeItem(_ payload: ItemPayload, section: GallerySection) -> GalleryItem? {
        guard let detail = payload.detailURL.flatMap(URL.init(string:)) else { return nil }
        let pageURLs = (payload.pageURLs ?? []).compactMap(URL.init(string:))
        let samples = (payload.sampleImageURLs ?? [])
            .compactMap(URL.init(string:))
            .map(GalleryImageURLNormalizer.normalized)
        let title = payload.displayTitle ?? payload.rawTitle ?? payload.id

        let coverURL = payload.coverURL.flatMap(URL.init(string:)).map(GalleryImageURLNormalizer.normalized) ?? samples.first
        return GalleryItem(
            id: payload.id,
            section: section,
            kind: section == .popular ? .recommended : .gallery,
            title: title,
            rawTitle: payload.rawTitle ?? title,
            subtitle: payload.subtitle ?? "4KHD 图集",
            detailURL: detail,
            coverURL: coverURL,
            coverAspectRatio: coverURL.flatMap(GalleryCoverAspectRatio.aspectRatio),
            imageCount: max(payload.imageCount ?? 0, samples.count),
            pageCount: max(payload.pageCount ?? 0, pageURLs.count, 1),
            pageURLs: pageURLs.isEmpty ? [detail] : pageURLs,
            sampleImageURLs: samples
        )
    }

}
