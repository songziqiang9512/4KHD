import Foundation

final class ApifyLibrary {
    private var itemsBySection: [GallerySection: [GalleryItem]]

    init() {
        itemsBySection = Dictionary(
            uniqueKeysWithValues: GallerySection.allCases
                .filter(\.isNetworkBacked)
                .map { ($0, []) }
        )
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

}
