import AppKit

extension LocalImageGridContainerView: NSCollectionViewDataSource {
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        entries.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        guard indexPath.item < entries.count,
              let item = collectionView.makeItem(
                withIdentifier: LocalImageGridItemView.reuseID,
                for: indexPath
              ) as? LocalImageGridItemView else {
            return NSCollectionViewItem()
        }

        let entry = entries[indexPath.item]
        item.configure(
            image: entry.image,
            fileExists: entry.metadata?.fileExists ?? true,
            isSelected: entry.image.id == selectedImageID
        ) { completion in
            guard FileManager.default.fileExists(atPath: entry.image.url.path) else {
                completion(.missingFile)
                return
            }
            Task { @MainActor in
                let image = await LocalImageCache.shared.image(for: entry.image.url, maxPixelSize: 512)
                completion(image.map(LocalImageThumbnailLoadResult.image) ?? .unavailable)
            }
        }
        return item
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
        guard indexPath.item < entries.count else { return nil }
        return entries[indexPath.item].image.url as NSURL
    }
}

extension LocalImageGridContainerView: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !isApplyingSelection,
              let indexPath = indexPaths.first,
              indexPath.item < entries.count else { return }
        selectItem(at: indexPath.item, scroll: false)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        willDisplay item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath
    ) {
        guard let item = item as? LocalImageGridItemView, indexPath.item < entries.count else { return }
        item.applySelectionState(entries[indexPath.item].image.id == selectedImageID)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        shouldDeselectItemsAt indexPaths: Set<IndexPath>
    ) -> Set<IndexPath> {
        []
    }
}
