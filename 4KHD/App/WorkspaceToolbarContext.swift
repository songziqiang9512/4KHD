import AppKit
import Foundation

enum WorkspaceToolbarSnapshot {
    case gallery(GallerySnapshot)
    case local(LocalSnapshot)

    struct GallerySnapshot {
        let searchText: String
        let layout: GalleryContentLayout
        let isRefreshing: Bool
    }

    struct LocalSnapshot {
        let searchText: String
        let layout: LocalContentLayout
        let sortField: LocalImageSortField
        let sortDirection: LocalImageSortDirection
        let isRefreshing: Bool
        let hasSelection: Bool
    }
}

@MainActor
final class WorkspaceToolbarContext {
    private let galleryStore: FourKHDGalleryStore
    private let galleryPreferences: GalleryContentPreferences
    private let galleryDetailInteraction: GalleryDetailInteractionController
    private let localLibraryStore: LocalLibraryStore
    private let localPreferences: LocalLibraryContentPreferences
    private let localDetailInteraction: LocalDetailInteractionController
    private let localInspector: LocalImageInspectorController
    private let filmstripVisibility: FilmstripVisibilityController
    private let importRootFolderAction: () -> Void

    init(
        galleryStore: FourKHDGalleryStore,
        galleryPreferences: GalleryContentPreferences,
        galleryDetailInteraction: GalleryDetailInteractionController,
        localLibraryStore: LocalLibraryStore,
        localPreferences: LocalLibraryContentPreferences,
        localDetailInteraction: LocalDetailInteractionController,
        localInspector: LocalImageInspectorController,
        filmstripVisibility: FilmstripVisibilityController,
        importRootFolderAction: @escaping () -> Void
    ) {
        self.galleryStore = galleryStore
        self.galleryPreferences = galleryPreferences
        self.galleryDetailInteraction = galleryDetailInteraction
        self.localLibraryStore = localLibraryStore
        self.localPreferences = localPreferences
        self.localDetailInteraction = localDetailInteraction
        self.localInspector = localInspector
        self.filmstripVisibility = filmstripVisibility
        self.importRootFolderAction = importRootFolderAction
    }

    func snapshot(for moduleID: WorkspaceModuleID) -> WorkspaceToolbarSnapshot {
        switch moduleID {
        case .fourKHDGallery:
            return .gallery(
                .init(
                    searchText: galleryStore.searchText,
                    layout: galleryPreferences.layout,
                    isRefreshing: galleryStore.isRefreshingList
                )
            )
        case .localLibrary:
            return .local(
                .init(
                    searchText: localPreferences.searchText,
                    layout: localPreferences.layout,
                    sortField: localPreferences.sortField,
                    sortDirection: localPreferences.sortDirection,
                    isRefreshing: localLibraryStore.isScanning,
                    hasSelection: localLibraryStore.selectedFolder != nil
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
        }
    }

    func submitSearch(for moduleID: WorkspaceModuleID) {
        switch moduleID {
        case .fourKHDGallery:
            galleryStore.submitSearch()
        case .localLibrary:
            break
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

    func refresh(for moduleID: WorkspaceModuleID) {
        switch moduleID {
        case .fourKHDGallery:
            galleryStore.refreshFromNetwork()
        case .localLibrary:
            localLibraryStore.refreshSelectedRoot()
        }
    }

    func importRootFolder() {
        importRootFolderAction()
    }

    func toggleFavorite() {
        guard let item = galleryStore.selectedItem else { return }
        galleryStore.toggleFavorite(for: item)
    }

    func resetDetailZoom(for moduleID: WorkspaceModuleID) {
        switch moduleID {
        case .fourKHDGallery:
            galleryDetailInteraction.resetZoom()
        case .localLibrary:
            localDetailInteraction.resetZoom()
        }
    }

    func toggleImmersive(_ immersive: ImmersiveController) {
        immersive.toggle()
    }

    func toggleFilmstrip() {
        filmstripVisibility.toggle()
    }

    func openOriginalPage() {
        guard let item = galleryStore.selectedItem else { return }
        NSWorkspace.shared.open(item.detailURL)
    }

    func revealInFinder() {
        guard let image = localLibraryStore.selectedImage else { return }
        NSWorkspace.shared.activateFileViewerSelecting([image.url])
    }

    func quickLookSelectedLocalImage() {
        guard let image = localLibraryStore.selectedImage else { return }
        LocalQuickLookController.shared.open(url: image.url)
    }

    func toggleLocalInspector() {
        guard let image = localLibraryStore.selectedImage else { return }
        localInspector.toggle(image)
    }

    func saveSelectedDetail(for moduleID: WorkspaceModuleID) {
        switch moduleID {
        case .fourKHDGallery:
            guard let item = galleryStore.selectedItem,
                  let slot = galleryStore.selectedSlot else { return }
            galleryDetailInteraction.save(item: item, slot: slot)
        case .localLibrary:
            guard let image = localLibraryStore.selectedImage else { return }
            localDetailInteraction.save(image: image)
        }
    }

    var isFilmstripPresented: Bool {
        filmstripVisibility.isPresented
    }
}
