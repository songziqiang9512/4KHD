import AppKit
import Foundation

enum WorkspaceToolbarSnapshot {
    case gallery(GallerySnapshot)
    case local(LocalSnapshot)

    struct GallerySnapshot {
        let searchText: String
        let layout: GalleryContentLayout
        let isRefreshing: Bool
        let canFavorite: Bool
        let isFavorite: Bool
        let canShare: Bool
    }

    struct LocalSnapshot {
        let searchText: String
        let layout: LocalContentLayout
        let sortField: LocalImageSortField
        let sortDirection: LocalImageSortDirection
        let isRefreshing: Bool
        let hasSelection: Bool
        let canShare: Bool
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
            let selectedItem = galleryStore.selectedItem
            return .gallery(
                .init(
                    searchText: galleryStore.searchText,
                    layout: galleryPreferences.layout,
                    isRefreshing: galleryStore.isRefreshingList,
                    canFavorite: selectedItem != nil,
                    isFavorite: selectedItem.map { galleryStore.isFavorite($0) } ?? false,
                    canShare: selectedItem != nil
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
                    hasSelection: localLibraryStore.selectedFolder != nil,
                    canShare: localLibraryStore.selectedImage != nil
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

    func shareItems(for moduleID: WorkspaceModuleID) -> [Any] {
        switch moduleID {
        case .fourKHDGallery:
            return galleryStore.selectedItem.map { [$0.detailURL] } ?? []
        case .localLibrary:
            return localLibraryStore.selectedImage.map { [$0.url as NSURL] } ?? []
        }
    }

    func currentReference(for moduleID: WorkspaceModuleID) -> WorkspaceCurrentReference? {
        switch moduleID {
        case .fourKHDGallery:
            return galleryStore.selectedItem.map { .web($0.detailURL) }
        case .localLibrary:
            return localLibraryStore.selectedImage.map { .file($0.url) }
        }
    }

    func toggleFavorite(for moduleID: WorkspaceModuleID) {
        guard case .fourKHDGallery = moduleID,
              let item = galleryStore.selectedItem else { return }
        galleryStore.toggleFavorite(for: item)
    }
}
