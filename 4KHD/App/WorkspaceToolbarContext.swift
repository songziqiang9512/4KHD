import AppKit
import Foundation

enum WorkspaceToolbarSnapshot {
    case gallery(GallerySnapshot)
    case local(LocalSnapshot)
    case missKon(MissKonSnapshot)

    struct GallerySnapshot {
        let searchText: String
        let layout: GalleryContentLayout
        let isRefreshing: Bool
        let canFavorite: Bool
        let isFavorite: Bool
        let canSelectPreviousImage: Bool
        let canSelectNextImage: Bool
        let canSaveImage: Bool
        let canResetZoom: Bool
        let canShare: Bool
        let isFilmstripPresented: Bool
    }

    struct MissKonSnapshot {
        let searchText: String
        let layout: MissKonContentLayout
        let isRefreshing: Bool
        let canIncreaseGridColumns: Bool
        let canDecreaseGridColumns: Bool
        let canSelectPreviousImage: Bool
        let canSelectNextImage: Bool
        let canSaveImage: Bool
        let canResetZoom: Bool
        let canShare: Bool
        let isFilmstripPresented: Bool
    }

    struct LocalSnapshot {
        let searchText: String
        let layout: LocalContentLayout
        let sortField: LocalImageSortField
        let sortDirection: LocalImageSortDirection
        let isRefreshing: Bool
        let hasSelection: Bool
        let canIncreaseGridColumns: Bool
        let canDecreaseGridColumns: Bool
        let canSelectPreviousImage: Bool
        let canSelectNextImage: Bool
        let canSaveImage: Bool
        let canResetZoom: Bool
        let canShare: Bool
        let isFilmstripPresented: Bool
    }
}

enum WorkspaceCurrentReference {
    case web(URL)
    case file(URL)

    var url: URL {
        switch self {
        case .web(let url), .file(let url):
            return url
        }
    }

    var fileURL: URL? {
        switch self {
        case .web:
            return nil
        case .file(let url):
            return url
        }
    }

    var copyMenuTitle: String {
        switch self {
        case .web:
            return "Copy Link"
        case .file:
            return "Copy Path"
        }
    }

    func writeToPasteboard(_ pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        switch self {
        case .web(let url):
            let urlString = url.absoluteString
            pasteboard.setString(urlString, forType: .URL)
            pasteboard.setString(urlString, forType: .string)
        case .file(let url):
            pasteboard.setString(url.path, forType: .string)
        }
    }
}

@MainActor
final class WorkspaceToolbarContext {
    private let galleryStore: FourKHDGalleryStore
    private let galleryPreferences: GalleryContentPreferences
    private let galleryDetailInteraction: GalleryDetailInteractionController
    private let missKonStore: MissKonGalleryStore
    private let missKonPreferences: MissKonContentPreferences
    private let missKonDetailInteraction: MissKonDetailInteractionController
    private let localLibraryStore: LocalLibraryStore
    private let localPreferences: LocalLibraryContentPreferences
    private let localDetailInteraction: LocalDetailInteractionController
    private let filmstripVisibility: FilmstripVisibilityController
    private let detailPaneController: WorkspaceDetailPaneController
    private let importRootFolderAction: () -> Void

    init(
        galleryStore: FourKHDGalleryStore,
        galleryPreferences: GalleryContentPreferences,
        galleryDetailInteraction: GalleryDetailInteractionController,
        missKonStore: MissKonGalleryStore,
        missKonPreferences: MissKonContentPreferences,
        missKonDetailInteraction: MissKonDetailInteractionController,
        localLibraryStore: LocalLibraryStore,
        localPreferences: LocalLibraryContentPreferences,
        localDetailInteraction: LocalDetailInteractionController,
        filmstripVisibility: FilmstripVisibilityController,
        detailPaneController: WorkspaceDetailPaneController,
        importRootFolderAction: @escaping () -> Void
    ) {
        self.galleryStore = galleryStore
        self.galleryPreferences = galleryPreferences
        self.galleryDetailInteraction = galleryDetailInteraction
        self.missKonStore = missKonStore
        self.missKonPreferences = missKonPreferences
        self.missKonDetailInteraction = missKonDetailInteraction
        self.localLibraryStore = localLibraryStore
        self.localPreferences = localPreferences
        self.localDetailInteraction = localDetailInteraction
        self.filmstripVisibility = filmstripVisibility
        self.detailPaneController = detailPaneController
        self.importRootFolderAction = importRootFolderAction
    }

    func snapshot(for moduleID: WorkspaceModuleID) -> WorkspaceToolbarSnapshot {
        switch moduleID {
        case .fourKHDGallery:
            let selectedItem = galleryStore.selectedItem
            return .gallery(
                .init(
                    searchText: galleryStore.searchText,
                    layout: galleryPreferences.layout,
                    isRefreshing: galleryStore.isRefreshingList,
                    canFavorite: selectedItem != nil,
                    isFavorite: selectedItem.map { galleryStore.isFavorite($0) } ?? false,
                    canSelectPreviousImage: galleryStore.selectedImageIndex > 0,
                    canSelectNextImage: selectedItem.map { item in
                        galleryStore.selectedImageIndex < max(item.imageCount - 1, 0)
                    } ?? false,
                    canSaveImage: selectedItem != nil && galleryStore.selectedSlot?.knownURL != nil,
                    canResetZoom: galleryStore.selectedSlot != nil,
                    canShare: selectedItem != nil,
                    isFilmstripPresented: filmstripVisibility.isPresented
                )
            )
        case .localLibrary:
            let selectedImageIndex = localLibraryStore.selectedImageIndex
            let imageCount = localLibraryStore.selectedImages.count
            let canAdjustGridColumns = localPreferences.layout == .grid
                && !detailPaneController.isPresented
            return .local(
                .init(
                    searchText: localPreferences.searchText,
                    layout: localPreferences.layout,
                    sortField: localPreferences.sortField,
                    sortDirection: localPreferences.sortDirection,
                    isRefreshing: localLibraryStore.isScanning,
                    hasSelection: !localLibraryStore.roots.isEmpty,
                    canIncreaseGridColumns: canAdjustGridColumns
                        && localPreferences.canIncreaseGridColumns,
                    canDecreaseGridColumns: canAdjustGridColumns
                        && localPreferences.canDecreaseGridColumns,
                    canSelectPreviousImage: selectedImageIndex > 0,
                    canSelectNextImage: selectedImageIndex < imageCount - 1,
                    canSaveImage: localLibraryStore.selectedImage != nil,
                    canResetZoom: localLibraryStore.selectedImage != nil,
                    canShare: localLibraryStore.selectedImage != nil,
                    isFilmstripPresented: filmstripVisibility.isPresented
                )
            )
        case .missKon:
            let slots = missKonStore.imageSlots
            let selectedIndex = missKonStore.selectedSlotID.flatMap { id in slots.firstIndex { $0.id == id } } ?? -1
            let haveImageURL: Bool = {
                guard let slot = missKonStore.selectedSlotID.flatMap({ id in slots.first { $0.id == id } }) else { return false }
                return slot.knownURL != nil || missKonStore.detail.imageURL(for: slot) != nil
            }()
            return .missKon(
                .init(
                    searchText: missKonStore.searchText,
                    layout: missKonPreferences.layout,
                    isRefreshing: missKonStore.isRefreshingList,
                    canIncreaseGridColumns: missKonPreferences.layout == .grid
                        && !detailPaneController.isPresented
                        && missKonPreferences.canIncreaseGridColumns,
                    canDecreaseGridColumns: missKonPreferences.layout == .grid
                        && !detailPaneController.isPresented
                        && missKonPreferences.canDecreaseGridColumns,
                    canSelectPreviousImage: selectedIndex > 0,
                    canSelectNextImage: selectedIndex < slots.count - 1,
                    canSaveImage: haveImageURL,
                    canResetZoom: missKonStore.selectedSlotID != nil,
                    canShare: missKonStore.currentItem != nil,
                    isFilmstripPresented: filmstripVisibility.isPresented
                )
            )
        }
    }

    func setSearchText(_ text: String, for moduleID: WorkspaceModuleID) {
        switch moduleID {
        case .fourKHDGallery:
            galleryStore.searchText = text
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               galleryStore.activeSearchQuery != nil {
                galleryStore.clearSearch()
            }
        case .localLibrary:
            localPreferences.searchText = text
        case .missKon:
            missKonStore.feed.searchText = text
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               missKonStore.activeSearchQuery != nil {
                missKonStore.clearSearch()
            }
        }
    }

    func submitSearch(for moduleID: WorkspaceModuleID) {
        switch moduleID {
        case .fourKHDGallery:
            galleryStore.submitSearch()
        case .localLibrary:
            break
        case .missKon:
            missKonStore.submitSearch(missKonStore.searchText)
        }
    }

    func setGalleryLayout(_ layout: GalleryContentLayout) {
        galleryPreferences.layout = layout
    }

    func setLocalLayout(_ layout: LocalContentLayout) {
        localPreferences.layout = layout
    }

    func setLocalSort(field: LocalImageSortField, direction: LocalImageSortDirection) {
        localPreferences.sortField = field
        localPreferences.sortDirection = direction
    }

    func adjustLocalGridColumns(delta: Int) {
        guard localPreferences.layout == .grid,
              !detailPaneController.isPresented else { return }
        localPreferences.adjustGridColumns(delta: delta)
    }

    func adjustMissKonGridColumns(delta: Int) {
        guard missKonPreferences.layout == .grid,
              !detailPaneController.isPresented else { return }
        missKonPreferences.adjustGridColumns(delta: delta)
    }

    func refresh(for moduleID: WorkspaceModuleID) {
        switch moduleID {
        case .fourKHDGallery:
            galleryStore.refreshFromNetwork()
        case .localLibrary:
            localLibraryStore.refreshSelectedRoot()
        case .missKon:
            missKonStore.refreshFromNetwork()
        }
    }

    func importRootFolder() {
        importRootFolderAction()
    }

    func shareItems(for moduleID: WorkspaceModuleID) -> [Any] {
        switch moduleID {
        case .fourKHDGallery:
            return galleryStore.selectedItem.map { [$0.detailURL] } ?? []
        case .localLibrary:
            return localLibraryStore.selectedImage.map { [$0.url as NSURL] } ?? []
        case .missKon:
            return missKonStore.currentItem.map { [$0.detailURL] } ?? []
        }
    }

    func currentReference(for moduleID: WorkspaceModuleID) -> WorkspaceCurrentReference? {
        switch moduleID {
        case .fourKHDGallery:
            return galleryStore.selectedItem.map { .web($0.detailURL) }
        case .localLibrary:
            return localLibraryStore.selectedImage.map { .file($0.url) }
        case .missKon:
            return missKonStore.currentItem.map { .web($0.detailURL) }
        }
    }

    func toggleFavorite(for moduleID: WorkspaceModuleID) {
        guard case .fourKHDGallery = moduleID,
              let item = galleryStore.selectedItem else { return }
        galleryStore.toggleFavorite(for: item)
    }

    func stepImage(_ delta: Int, for moduleID: WorkspaceModuleID) {
        switch moduleID {
        case .fourKHDGallery:
            galleryStore.stepImage(delta)
        case .localLibrary:
            localLibraryStore.stepImage(delta)
        case .missKon:
            guard delta != 0 else { return }
            let slots = missKonStore.imageSlots
            guard !slots.isEmpty else { return }
            let current = missKonStore.selectedSlotID.flatMap { id in slots.firstIndex { $0.id == id } } ?? 0
            let next = min(max(current + delta, 0), slots.count - 1)
            guard next != current else { return }
            missKonStore.detail.selectSlot(at: next)
        }
    }

    func saveCurrentImage(for moduleID: WorkspaceModuleID) {
        switch moduleID {
        case .fourKHDGallery:
            guard let item = galleryStore.selectedItem,
                  let slot = galleryStore.selectedSlot else { return }
            galleryDetailInteraction.save(item: item, slot: slot)
        case .localLibrary:
            guard let image = localLibraryStore.selectedImage else { return }
            localDetailInteraction.save(image: image)
        case .missKon:
            guard let slot = missKonStore.selectedSlotID.flatMap({ id in missKonStore.imageSlots.first { $0.id == id } }),
                  let url = slot.knownURL ?? missKonStore.detail.imageURL(for: slot) else { return }
            let filename = "\(missKonStore.currentItem?.id ?? "misskon")-\(slot.displayIndex + 1).jpg"
            missKonDetailInteraction.save(imageURL: url, filename: filename)
        }
    }

    func resetZoom(for moduleID: WorkspaceModuleID) {
        switch moduleID {
        case .fourKHDGallery:
            galleryDetailInteraction.resetZoom()
        case .localLibrary:
            localDetailInteraction.resetZoom()
        case .missKon:
            missKonDetailInteraction.resetZoom()
        }
    }

    func toggleFilmstrip() {
        filmstripVisibility.toggle()
    }
}
