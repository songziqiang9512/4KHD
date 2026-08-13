import AppKit
import Foundation

enum WorkspaceToolbarSnapshot {
    case gallery(GallerySnapshot)
    case local(LocalSnapshot)
    case missKon(MissKonSnapshot)
    case wallhaven(WallhavenSnapshot)

    struct GallerySnapshot {
        let searchText: String
        let layout: GalleryContentLayout
        let isRefreshing: Bool
        let canFavorite: Bool
        let isFavorite: Bool
        let canIncreaseGridColumns: Bool
        let canDecreaseGridColumns: Bool
        let canSelectPreviousImage: Bool
        let canSelectNextImage: Bool
        let canSaveImage: Bool
        let canSaveAlbum: Bool
        let canResetZoom: Bool
        let canShare: Bool
        let isFilmstripPresented: Bool
    }

    struct MissKonSnapshot {
        let searchText: String
        let layout: MissKonContentLayout
        let isRefreshing: Bool
        let canFavorite: Bool
        let isFavorite: Bool
        let canIncreaseGridColumns: Bool
        let canDecreaseGridColumns: Bool
        let canSelectPreviousImage: Bool
        let canSelectNextImage: Bool
        let canSaveImage: Bool
        let canSaveAlbum: Bool
        let canResetZoom: Bool
        let canShare: Bool
        let isFilmstripPresented: Bool
    }

    struct WallhavenSnapshot {
        let searchText: String
        let layout: WallhavenContentLayout
        let isRefreshing: Bool
        let canFavorite: Bool
        let isFavorite: Bool
        let canIncreaseGridColumns: Bool
        let canDecreaseGridColumns: Bool
        let canSelectPreviousImage: Bool
        let canSelectNextImage: Bool
        let canSaveImage: Bool
        let canResetZoom: Bool
        let canShare: Bool
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

    /// Extracts common fields for toolbar display, eliminating the need
    /// for repeated 4-way switches in WorkspaceToolbarHost.
    struct CommonFields {
        let moduleName: String
        let searchText: String
        let isRefreshing: Bool
        let canFavorite: Bool
        let isFavorite: Bool
        let canIncreaseGridColumns: Bool
        let canDecreaseGridColumns: Bool
        let canSelectPreviousImage: Bool
        let canSelectNextImage: Bool
        let canSaveImage: Bool
        let canResetZoom: Bool
        let canShare: Bool
        let isFilmstripPresented: Bool
        let hasSelection: Bool
    }

    var fields: CommonFields {
        switch self {
        case .gallery(let s):
            CommonFields(
                moduleName: "4KHD", searchText: s.searchText,
                isRefreshing: s.isRefreshing,
                canFavorite: s.canFavorite, isFavorite: s.isFavorite,
                canIncreaseGridColumns: s.canIncreaseGridColumns,
                canDecreaseGridColumns: s.canDecreaseGridColumns,
                canSelectPreviousImage: s.canSelectPreviousImage,
                canSelectNextImage: s.canSelectNextImage,
                canSaveImage: s.canSaveImage, canResetZoom: s.canResetZoom,
                canShare: s.canShare, isFilmstripPresented: s.isFilmstripPresented,
                hasSelection: s.canShare
            )
        case .local(let s):
            CommonFields(
                moduleName: "本地图片", searchText: s.searchText,
                isRefreshing: s.isRefreshing,
                canFavorite: false, isFavorite: false,
                canIncreaseGridColumns: s.canIncreaseGridColumns,
                canDecreaseGridColumns: s.canDecreaseGridColumns,
                canSelectPreviousImage: s.canSelectPreviousImage,
                canSelectNextImage: s.canSelectNextImage,
                canSaveImage: s.canSaveImage, canResetZoom: s.canResetZoom,
                canShare: s.canShare, isFilmstripPresented: s.isFilmstripPresented,
                hasSelection: s.hasSelection
            )
        case .missKon(let s):
            CommonFields(
                moduleName: "MissKon", searchText: s.searchText,
                isRefreshing: s.isRefreshing,
                canFavorite: s.canFavorite, isFavorite: s.isFavorite,
                canIncreaseGridColumns: s.canIncreaseGridColumns,
                canDecreaseGridColumns: s.canDecreaseGridColumns,
                canSelectPreviousImage: s.canSelectPreviousImage,
                canSelectNextImage: s.canSelectNextImage,
                canSaveImage: s.canSaveImage, canResetZoom: s.canResetZoom,
                canShare: s.canShare, isFilmstripPresented: s.isFilmstripPresented,
                hasSelection: s.canShare
            )
        case .wallhaven(let s):
            CommonFields(
                moduleName: "Wallhaven", searchText: s.searchText,
                isRefreshing: s.isRefreshing,
                canFavorite: s.canFavorite, isFavorite: s.isFavorite,
                canIncreaseGridColumns: s.canIncreaseGridColumns,
                canDecreaseGridColumns: s.canDecreaseGridColumns,
                canSelectPreviousImage: s.canSelectPreviousImage,
                canSelectNextImage: s.canSelectNextImage,
                canSaveImage: s.canSaveImage, canResetZoom: s.canResetZoom,
                canShare: s.canShare, isFilmstripPresented: false,
                hasSelection: s.canShare
            )
        }
    }

    var isListLayout: Bool {
        switch self {
        case .gallery(let snapshot):
            snapshot.layout == .list
        case .local(let snapshot):
            snapshot.layout == .list
        case .missKon(let snapshot):
            snapshot.layout == .list
        case .wallhaven(let snapshot):
            snapshot.layout == .list
        }
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
    private let wallhavenStore: WallhavenGalleryStore
    private let wallhavenPreferences: WallhavenContentPreferences
    private let wallhavenDetailInteraction: WallhavenDetailInteractionController
    private let localLibraryStore: LocalLibraryStore
    private let localPreferences: LocalLibraryContentPreferences
    private let localDetailInteraction: LocalDetailInteractionController
    private let filmstripVisibility: FilmstripVisibilityController
    private let detailPaneController: WorkspaceDetailPaneController
    private let downloadStore: DownloadStore
    private let importRootFolderAction: () -> Void

    init(
        galleryStore: FourKHDGalleryStore,
        galleryPreferences: GalleryContentPreferences,
        galleryDetailInteraction: GalleryDetailInteractionController,
        missKonStore: MissKonGalleryStore,
        missKonPreferences: MissKonContentPreferences,
        missKonDetailInteraction: MissKonDetailInteractionController,
        wallhavenStore: WallhavenGalleryStore,
        wallhavenPreferences: WallhavenContentPreferences,
        wallhavenDetailInteraction: WallhavenDetailInteractionController,
        localLibraryStore: LocalLibraryStore,
        localPreferences: LocalLibraryContentPreferences,
        localDetailInteraction: LocalDetailInteractionController,
        filmstripVisibility: FilmstripVisibilityController,
        detailPaneController: WorkspaceDetailPaneController,
        downloadStore: DownloadStore,
        importRootFolderAction: @escaping () -> Void
    ) {
        self.galleryStore = galleryStore
        self.galleryPreferences = galleryPreferences
        self.galleryDetailInteraction = galleryDetailInteraction
        self.missKonStore = missKonStore
        self.missKonPreferences = missKonPreferences
        self.missKonDetailInteraction = missKonDetailInteraction
        self.wallhavenStore = wallhavenStore
        self.wallhavenPreferences = wallhavenPreferences
        self.wallhavenDetailInteraction = wallhavenDetailInteraction
        self.localLibraryStore = localLibraryStore
        self.localPreferences = localPreferences
        self.localDetailInteraction = localDetailInteraction
        self.filmstripVisibility = filmstripVisibility
        self.detailPaneController = detailPaneController
        self.downloadStore = downloadStore
        self.importRootFolderAction = importRootFolderAction
    }

    func snapshot(for moduleID: WorkspaceModuleID) -> WorkspaceToolbarSnapshot {
        switch moduleID {
        case .fourKHDGallery:
            let selectedItem = galleryStore.selectedItem
            let canAdjustGridColumns = galleryPreferences.layout == .grid
                && !detailPaneController.isPresented
            return .gallery(
                .init(
                    searchText: galleryStore.searchText,
                    layout: galleryPreferences.layout,
                    isRefreshing: galleryStore.isRefreshingList,
                    canFavorite: selectedItem != nil,
                    isFavorite: selectedItem.map { galleryStore.isFavorite($0) } ?? false,
                    canIncreaseGridColumns: canAdjustGridColumns && galleryPreferences.canIncreaseGridColumns,
                    canDecreaseGridColumns: canAdjustGridColumns && galleryPreferences.canDecreaseGridColumns,
                    canSelectPreviousImage: galleryStore.selectedImageIndex > 0,
                    canSelectNextImage: selectedItem.map { item in
                        galleryStore.selectedImageIndex < max(item.imageCount - 1, 0)
                    } ?? false,
                    canSaveImage: selectedItem != nil && galleryStore.selectedSlot?.knownURL != nil,
                    canSaveAlbum: selectedItem != nil,
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
            let currentItem = missKonStore.currentItem
            return .missKon(
                .init(
                    searchText: missKonStore.searchText,
                    layout: missKonPreferences.layout,
                    isRefreshing: missKonStore.isRefreshingList,
                    canFavorite: currentItem != nil,
                    isFavorite: currentItem.map { missKonStore.isFavorite($0) } ?? false,
                    canIncreaseGridColumns: missKonPreferences.layout == .grid
                        && !detailPaneController.isPresented
                        && missKonPreferences.canIncreaseGridColumns,
                    canDecreaseGridColumns: missKonPreferences.layout == .grid
                        && !detailPaneController.isPresented
                        && missKonPreferences.canDecreaseGridColumns,
                    canSelectPreviousImage: selectedIndex > 0,
                    canSelectNextImage: selectedIndex >= 0 && selectedIndex < slots.count - 1,
                    canSaveImage: haveImageURL,
                    canSaveAlbum: currentItem != nil,
                    canResetZoom: missKonStore.selectedSlotID != nil,
                    canShare: currentItem != nil,
                    isFilmstripPresented: filmstripVisibility.isPresented
                )
            )
        case .wallhaven:
            let wallpapers = wallhavenStore.wallpapers
            let selectedIndex = wallhavenStore.selectedWallpaperID.flatMap { id in wallpapers.firstIndex { $0.id == id } } ?? -1
            let effective = wallhavenStore.effectiveSelectedWallpaper
            return .wallhaven(
                .init(
                    searchText: wallhavenStore.searchText,
                    layout: wallhavenPreferences.layout,
                    isRefreshing: wallhavenStore.isRefreshingList,
                    canFavorite: effective != nil,
                    isFavorite: effective.map { wallhavenStore.isFavorite($0) } ?? false,
                    canIncreaseGridColumns: wallhavenPreferences.layout == .grid
                        && !detailPaneController.isPresented
                        && wallhavenPreferences.canIncreaseGridColumns,
                    canDecreaseGridColumns: wallhavenPreferences.layout == .grid
                        && !detailPaneController.isPresented
                        && wallhavenPreferences.canDecreaseGridColumns,
                    canSelectPreviousImage: selectedIndex > 0,
                    canSelectNextImage: selectedIndex >= 0 && selectedIndex < wallpapers.count - 1,
                    canSaveImage: effective?.fullImageUrl != nil,
                    canResetZoom: effective != nil,
                    canShare: effective != nil
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
        case .wallhaven:
            wallhavenStore.setSearchText(text)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               wallhavenStore.activeSearchQuery != nil {
                wallhavenStore.clearSearch()
            }
        }
    }

    func setLayout(isList: Bool, for moduleID: WorkspaceModuleID) {
        switch moduleID {
        case .fourKHDGallery:
            setGalleryLayout(isList ? .list : .grid)
        case .localLibrary:
            setLocalLayout(isList ? .list : .grid)
        case .missKon:
            setMissKonLayout(isList ? .list : .grid)
        case .wallhaven:
            setWallhavenLayout(isList ? .list : .grid)
        }
    }

    func adjustGridColumns(delta: Int, for moduleID: WorkspaceModuleID) {
        switch moduleID {
        case .fourKHDGallery:
            adjustGalleryGridColumns(delta: delta)
        case .localLibrary:
            adjustLocalGridColumns(delta: delta)
        case .missKon:
            adjustMissKonGridColumns(delta: delta)
        case .wallhaven:
            adjustWallhavenGridColumns(delta: delta)
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
        case .wallhaven:
            wallhavenStore.submitSearch(wallhavenStore.searchText)
        }
    }

    func setGalleryLayout(_ layout: GalleryContentLayout) {
        galleryPreferences.layout = layout
    }

    func setMissKonLayout(_ layout: MissKonContentLayout) {
        missKonPreferences.layout = layout
    }

    func setWallhavenLayout(_ layout: WallhavenContentLayout) {
        wallhavenPreferences.layout = layout
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

    func adjustGalleryGridColumns(delta: Int) {
        guard galleryPreferences.layout == .grid,
              !detailPaneController.isPresented else { return }
        galleryPreferences.adjustGridColumns(delta: delta)
    }

    func refresh(for moduleID: WorkspaceModuleID) {
        switch moduleID {
        case .fourKHDGallery:
            galleryStore.refreshFromNetwork()
        case .localLibrary:
            localLibraryStore.refreshSelectedRoot()
        case .missKon:
            missKonStore.refreshFromNetwork()
        case .wallhaven:
            wallhavenStore.refreshFromNetwork()
        }
    }

    func adjustWallhavenGridColumns(delta: Int) {
        guard wallhavenPreferences.layout == .grid,
              !detailPaneController.isPresented else { return }
        wallhavenPreferences.adjustGridColumns(delta: delta)
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
        case .wallhaven:
            return wallhavenStore.selectedWallpaper.map { [$0.sourcePageUrl] } ?? []
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
        case .wallhaven:
            return wallhavenStore.selectedWallpaper.map { .web($0.sourcePageUrl) }
        }
    }

    func toggleFavorite(for moduleID: WorkspaceModuleID) {
        Task { [weak self] in
            guard let self else { return }
            do {
                switch moduleID {
                case .fourKHDGallery:
                    guard let item = galleryStore.selectedItem else { return }
                    try await galleryStore.toggleFavorite(for: item)
                case .missKon:
                    guard let item = missKonStore.currentItem else { return }
                    try await missKonStore.toggleFavorite(for: item)
                case .wallhaven:
                    guard let wallpaper = wallhavenStore.selectedWallpaper else { return }
                    try await wallhavenStore.toggleFavorite(for: wallpaper)
                case .localLibrary:
                    return
                }
            } catch {
                let alert = makeAppAlert(
                    title: "收藏保存失败",
                    message: error.localizedDescription,
                    style: .warning
                )
                presentAppAlert(alert, in: appModalHostWindow())
            }
        }
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
        case .wallhaven:
            guard delta != 0 else { return }
            let wallpapers = wallhavenStore.wallpapers
            guard !wallpapers.isEmpty else { return }
            let current = wallhavenStore.selectedWallpaperID.flatMap { id in wallpapers.firstIndex { $0.id == id } } ?? 0
            let next = min(max(current + delta, 0), wallpapers.count - 1)
            guard next != current else { return }
            wallhavenStore.select(wallpapers[next])
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
        case .wallhaven:
            guard let wallpaper = wallhavenStore.effectiveSelectedWallpaper else { return }
            wallhavenDetailInteraction.saveWallpaper(wallpaper)
        }
    }

    func saveGalleryItem(for moduleID: WorkspaceModuleID) {
        let result: DownloadStore.EnqueueAlbumResult?
        switch moduleID {
        case .fourKHDGallery:
            guard let item = galleryStore.selectedItem else { return }
            result = downloadStore.enqueueAlbumChoosingFolder(source: .gallery(item))
        case .missKon:
            guard let item = missKonStore.currentItem else { return }
            result = downloadStore.enqueueAlbumChoosingFolder(source: .missKon(item))
        case .localLibrary, .wallhaven:
            return
        }
        if result == .duplicate {
            let alert = makeAppAlert(
                title: "该图集已在下载队列中",
                message: "同一下载任务正在排队或下载中。",
                style: .informational
            )
            presentAppAlert(alert, in: appModalHostWindow())
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
        case .wallhaven:
            wallhavenDetailInteraction.resetZoom()
        }
    }

    func toggleFilmstrip() {
        filmstripVisibility.toggle()
    }
}
