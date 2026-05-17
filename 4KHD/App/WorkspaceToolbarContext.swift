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
    private let localLibraryStore: LocalLibraryStore
    private let localPreferences: LocalLibraryContentPreferences
    private let importRootFolderAction: () -> Void

    init(
        galleryStore: FourKHDGalleryStore,
        galleryPreferences: GalleryContentPreferences,
        localLibraryStore: LocalLibraryStore,
        localPreferences: LocalLibraryContentPreferences,
        importRootFolderAction: @escaping () -> Void
    ) {
        self.galleryStore = galleryStore
        self.galleryPreferences = galleryPreferences
        self.localLibraryStore = localLibraryStore
        self.localPreferences = localPreferences
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
}
