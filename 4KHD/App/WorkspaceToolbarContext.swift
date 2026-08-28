import AppKit
import Foundation

enum WorkspaceToolbarSnapshot {
    case gallery(GallerySnapshot)
    case local(LocalSnapshot)
    case missKon(MissKonSnapshot)
    case wallhaven(WallhavenSnapshot)
    case favorites(FavoritesSnapshot)
    case knit(KnitSnapshot)

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

    struct KnitSnapshot {
        let searchText: String
        let layout: KnitContentLayout
        let filter: KnitBrowseFilter
        let pageStatusText: String
        let isRefreshing: Bool
        let canFavorite: Bool
        let isFavorite: Bool
        let canIncreaseGridColumns: Bool
        let canDecreaseGridColumns: Bool
        let canSelectPreviousImage: Bool
        let canSelectNextImage: Bool
        let canSaveImage: Bool
        let canSaveAlbum: Bool
        let canSaveVideo: Bool
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

    /// 统一收藏模块:收藏按钮恒为「取消收藏」语义。
    struct FavoritesSnapshot {
        let searchText: String
        let layout: FavoritesContentLayout
        let canFavorite: Bool
        let isFavorite: Bool
        let canIncreaseGridColumns: Bool
        let canDecreaseGridColumns: Bool
        let canSelectPreviousImage: Bool
        let canSelectNextImage: Bool
        let canSaveImage: Bool
        let canSaveAlbum: Bool
        let canSaveVideo: Bool
        let canResetZoom: Bool
        let canShare: Bool
        let canUseFilmstrip: Bool
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
        let canSaveAlbum: Bool
        let canSaveVideo: Bool
        let canResetZoom: Bool
        let canShare: Bool
        let canUseFilmstrip: Bool
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
                canSaveImage: s.canSaveImage, canSaveAlbum: s.canSaveAlbum, canSaveVideo: false,
                canResetZoom: s.canResetZoom,
                canShare: s.canShare, canUseFilmstrip: true,
                isFilmstripPresented: s.isFilmstripPresented,
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
                canSaveImage: s.canSaveImage, canSaveAlbum: false, canSaveVideo: false,
                canResetZoom: s.canResetZoom,
                canShare: s.canShare, canUseFilmstrip: true,
                isFilmstripPresented: s.isFilmstripPresented,
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
                canSaveImage: s.canSaveImage, canSaveAlbum: s.canSaveAlbum, canSaveVideo: false,
                canResetZoom: s.canResetZoom,
                canShare: s.canShare, canUseFilmstrip: true,
                isFilmstripPresented: s.isFilmstripPresented,
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
                canSaveImage: s.canSaveImage, canSaveAlbum: false, canSaveVideo: false,
                canResetZoom: s.canResetZoom,
                canShare: s.canShare, canUseFilmstrip: false, isFilmstripPresented: false,
                hasSelection: s.canShare
            )
        case .favorites(let s):
            CommonFields(
                moduleName: "在线收藏", searchText: s.searchText,
                isRefreshing: false,
                canFavorite: s.canFavorite, isFavorite: s.isFavorite,
                canIncreaseGridColumns: s.canIncreaseGridColumns,
                canDecreaseGridColumns: s.canDecreaseGridColumns,
                canSelectPreviousImage: s.canSelectPreviousImage,
                canSelectNextImage: s.canSelectNextImage,
                canSaveImage: s.canSaveImage, canSaveAlbum: s.canSaveAlbum, canSaveVideo: s.canSaveVideo,
                canResetZoom: s.canResetZoom,
                canShare: s.canShare, canUseFilmstrip: s.canUseFilmstrip,
                isFilmstripPresented: s.isFilmstripPresented,
                hasSelection: s.canShare
            )
        case .knit(let s):
            CommonFields(
                moduleName: "爱妹子", searchText: s.searchText,
                isRefreshing: s.isRefreshing,
                canFavorite: s.canFavorite, isFavorite: s.isFavorite,
                canIncreaseGridColumns: s.canIncreaseGridColumns,
                canDecreaseGridColumns: s.canDecreaseGridColumns,
                canSelectPreviousImage: s.canSelectPreviousImage,
                canSelectNextImage: s.canSelectNextImage,
                canSaveImage: s.canSaveImage, canSaveAlbum: s.canSaveAlbum, canSaveVideo: s.canSaveVideo,
                canResetZoom: s.canResetZoom,
                canShare: s.canShare, canUseFilmstrip: true,
                isFilmstripPresented: s.isFilmstripPresented,
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
        case .favorites(let snapshot):
            snapshot.layout == .list
        case .knit(let snapshot):
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
            return "复制链接"
        case .file:
            return "复制路径"
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
    private let knitStore: KnitGalleryStore
    private let knitPreferences: KnitContentPreferences
    private let knitDetailInteraction: KnitDetailInteractionController
    private let localLibraryStore: LocalLibraryStore
    private let localPreferences: LocalLibraryContentPreferences
    private let localDetailInteraction: LocalDetailInteractionController
    private let favoritesModuleStore: FavoritesModuleStore
    private let favoritesPreferences: FavoritesContentPreferences
    private let favoritesDetailStore: FavoritesDetailStore
    private let favoritesDetailInteraction: FavoritesDetailInteractionController
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
        knitStore: KnitGalleryStore,
        knitPreferences: KnitContentPreferences,
        knitDetailInteraction: KnitDetailInteractionController,
        localLibraryStore: LocalLibraryStore,
        localPreferences: LocalLibraryContentPreferences,
        localDetailInteraction: LocalDetailInteractionController,
        favoritesModuleStore: FavoritesModuleStore,
        favoritesPreferences: FavoritesContentPreferences,
        favoritesDetailStore: FavoritesDetailStore,
        favoritesDetailInteraction: FavoritesDetailInteractionController,
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
        self.knitStore = knitStore
        self.knitPreferences = knitPreferences
        self.knitDetailInteraction = knitDetailInteraction
        self.localLibraryStore = localLibraryStore
        self.localPreferences = localPreferences
        self.localDetailInteraction = localDetailInteraction
        self.favoritesModuleStore = favoritesModuleStore
        self.favoritesPreferences = favoritesPreferences
        self.favoritesDetailStore = favoritesDetailStore
        self.favoritesDetailInteraction = favoritesDetailInteraction
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
                    canSelectPreviousImage: galleryStore.canStepDetailBackward,
                    canSelectNextImage: galleryStore.canStepDetailForward,
                    canSaveImage: galleryStore.detailContentMode == .image
                        && selectedItem != nil
                        && galleryStore.selectedSlot?.knownURL != nil,
                    canSaveAlbum: selectedItem != nil,
                    canResetZoom: galleryStore.detailContentMode == .image
                        && galleryStore.selectedSlot != nil,
                    canShare: selectedItem != nil,
                    isFilmstripPresented: filmstripVisibility.isPresented
                )
            )
        case .localLibrary:
            let selectedImageIndex = localLibraryStore.selectedImageIndex
            let imageCount = localLibraryStore.selectedImages.count
            let hasLocalRoot = !localLibraryStore.roots.isEmpty
            let canAdjustGridColumns = localPreferences.layout == .grid
                && !detailPaneController.isPresented
            return .local(
                .init(
                    searchText: localPreferences.searchText,
                    layout: localPreferences.layout,
                    sortField: localPreferences.sortField,
                    sortDirection: localPreferences.sortDirection,
                    isRefreshing: localLibraryStore.isScanning,
                    hasSelection: hasLocalRoot,
                    canIncreaseGridColumns: hasLocalRoot && canAdjustGridColumns
                        && localPreferences.canIncreaseGridColumns,
                    canDecreaseGridColumns: hasLocalRoot && canAdjustGridColumns
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
                    canSelectPreviousImage: missKonStore.canStepDetailBackward,
                    canSelectNextImage: missKonStore.canStepDetailForward,
                    canSaveImage: missKonStore.detailContentMode == .image && haveImageURL,
                    canSaveAlbum: currentItem != nil,
                    canResetZoom: missKonStore.detailContentMode == .image
                        && missKonStore.selectedSlotID != nil,
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
        case .favorites:
            let selectedRecord = favoritesModuleStore.selectedRecord
            let source = selectedRecord.flatMap(FavoriteSource.source(for:))
            let canSaveAlbum = source == .gallery || source == .missKon || source == .knit
            let detailMatchesSelection = selectedRecord != nil
                && favoritesDetailStore.currentRecord == selectedRecord
            let canAdjustGridColumns = favoritesPreferences.layout == .grid
                && !detailPaneController.isPresented
            let canSelectPrevious: Bool
            let canSelectNext: Bool
            if detailMatchesSelection,
               let selectedRecord,
               favoritesDetailStore.navigationMode == .sourceRecords {
                canSelectPrevious = favoritesModuleStore.canStepSourceRecord(from: selectedRecord, delta: -1)
                canSelectNext = favoritesModuleStore.canStepSourceRecord(from: selectedRecord, delta: 1)
            } else {
                canSelectPrevious = detailMatchesSelection && favoritesDetailStore.canStepBackward
                canSelectNext = detailMatchesSelection && favoritesDetailStore.canStepForward
            }
            return .favorites(
                .init(
                    searchText: favoritesModuleStore.searchText,
                    layout: favoritesPreferences.layout,
                    canFavorite: selectedRecord != nil,
                    isFavorite: selectedRecord != nil,
                    canIncreaseGridColumns: canAdjustGridColumns
                        && favoritesPreferences.canIncreaseGridColumns,
                    canDecreaseGridColumns: canAdjustGridColumns
                        && favoritesPreferences.canDecreaseGridColumns,
                    canSelectPreviousImage: canSelectPrevious,
                    canSelectNextImage: canSelectNext,
                    canSaveImage: detailMatchesSelection
                        && favoritesDetailStore.contentMode == .image
                        && favoritesDetailStore.hasResolvedSelectedImage,
                    canSaveAlbum: canSaveAlbum,
                    canSaveVideo: detailMatchesSelection && favoritesDetailStore.canSaveVideo,
                    canResetZoom: detailMatchesSelection
                        && favoritesDetailStore.contentMode == .image
                        && favoritesDetailStore.selectedSlot != nil,
                    canShare: selectedRecord != nil,
                    canUseFilmstrip: detailMatchesSelection
                        && source != .wallhaven
                        && favoritesDetailStore.navigationMode == .images,
                    isFilmstripPresented: filmstripVisibility.isPresented
                )
            )
        case .knitGallery:
            let item = knitStore.selectedItem
            let canAdjust = knitPreferences.layout == .grid && !detailPaneController.isPresented
            return .knit(
                .init(
                    searchText: knitStore.searchText,
                    layout: knitPreferences.layout,
                    filter: knitStore.filter,
                    pageStatusText: knitStore.pageStatusText,
                    isRefreshing: knitStore.isRefreshingList,
                    canFavorite: item != nil,
                    isFavorite: item.map { knitStore.isFavorite($0) } ?? false,
                    canIncreaseGridColumns: canAdjust && knitPreferences.canIncreaseGridColumns,
                    canDecreaseGridColumns: canAdjust && knitPreferences.canDecreaseGridColumns,
                    canSelectPreviousImage: knitStore.canStepDetailBackward,
                    canSelectNextImage: knitStore.canStepDetailForward,
                    canSaveImage: knitStore.detailContentMode == .image
                        && item != nil
                        && knitStore.hasResolvedSelectedImage,
                    canSaveAlbum: item != nil,
                    canSaveVideo: item != nil && knitStore.videoURL != nil,
                    canResetZoom: knitStore.detailContentMode == .image
                        && knitStore.selectedSlot != nil,
                    canShare: item != nil,
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
        case .wallhaven:
            wallhavenStore.setSearchText(text)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               wallhavenStore.activeSearchQuery != nil {
                wallhavenStore.clearSearch()
            }
        case .favorites:
            favoritesModuleStore.searchText = text
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               favoritesModuleStore.activeSearchQuery != nil {
                favoritesModuleStore.clearSearch()
            }
        case .knitGallery:
            knitStore.searchText = text
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               knitStore.activeSearchQuery != nil {
                knitStore.clearSearch()
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
        case .favorites:
            favoritesPreferences.layout = isList ? .list : .grid
        case .knitGallery:
            knitPreferences.layout = isList ? .list : .grid
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
        case .favorites:
            guard favoritesPreferences.layout == .grid,
                  !detailPaneController.isPresented else { return }
            favoritesPreferences.adjustGridColumns(delta: delta)
        case .knitGallery:
            guard knitPreferences.layout == .grid, !detailPaneController.isPresented else { return }
            knitPreferences.adjustGridColumns(delta: delta)
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
        case .favorites:
            favoritesModuleStore.submitSearch()
        case .knitGallery:
            knitStore.submitSearch()
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
        case .favorites:
            // 重读磁盘快照后,visibleRecords 经观察链自动重建。
            Task { [weak self] in
                guard let self else { return }
                await favoritesModuleStore.favoritesStore.reloadFromDisk()
            }
        case .knitGallery:
            knitStore.refreshFromNetwork()
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
        case .favorites:
            return favoritesModuleStore.selectedRecord
                .flatMap { URL(string: $0.detailURL) }
                .map { [$0] } ?? []
        case .knitGallery:
            return knitStore.selectedItem.map { [$0.detailURL] } ?? []
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
        case .favorites:
            return favoritesModuleStore.selectedRecord
                .flatMap { URL(string: $0.detailURL) }
                .map { .web($0) }
        case .knitGallery:
            return knitStore.selectedItem.map { .web($0.detailURL) }
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
                case .favorites:
                    // 收藏列表里的收藏项已处于收藏态,toggle 即取消收藏。
                    guard let record = favoritesModuleStore.selectedRecord,
                          let recordURL = URL(string: record.detailURL) else { return }
                    let matched = favoritesModuleStore.favoritesStore.favorites
                        .first { $0.detailURL == recordURL.absoluteString } ?? record
                    try await favoritesModuleStore.favoritesStore.toggle(matched)
                case .knitGallery:
                    guard let item = knitStore.selectedItem else { return }
                    try await knitStore.toggleFavorite(for: item)
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
            missKonStore.detail.stepSelection(delta)
        case .wallhaven:
            guard delta != 0 else { return }
            let wallpapers = wallhavenStore.wallpapers
            guard !wallpapers.isEmpty else { return }
            let current = wallhavenStore.selectedWallpaperID.flatMap { id in wallpapers.firstIndex { $0.id == id } } ?? 0
            let next = min(max(current + delta, 0), wallpapers.count - 1)
            guard next != current else { return }
            wallhavenStore.select(wallpapers[next])
        case .favorites:
            guard let record = favoritesModuleStore.selectedRecord,
                  record == favoritesDetailStore.currentRecord else { return }
            switch favoritesDetailStore.navigationMode {
            case .images:
                favoritesDetailStore.stepSelection(delta)
            case .sourceRecords:
                favoritesModuleStore.stepSourceRecord(from: record, delta: delta)
            }
        case .knitGallery:
            knitStore.stepImage(delta)
        }
    }

    func saveCurrentImage(for moduleID: WorkspaceModuleID) {
        switch moduleID {
        case .fourKHDGallery:
            guard galleryStore.detailContentMode == .image,
                  let item = galleryStore.selectedItem,
                  let slot = galleryStore.selectedSlot else { return }
            galleryDetailInteraction.save(item: item, slot: slot)
        case .localLibrary:
            guard let image = localLibraryStore.selectedImage else { return }
            localDetailInteraction.save(image: image)
        case .missKon:
            guard missKonStore.detailContentMode == .image,
                  let slot = missKonStore.selectedSlotID.flatMap({ id in missKonStore.imageSlots.first { $0.id == id } }),
                  let url = slot.knownURL ?? missKonStore.detail.imageURL(for: slot) else { return }
            let filename = "\(missKonStore.currentItem?.id ?? "misskon")-\(slot.displayIndex + 1).jpg"
            missKonDetailInteraction.save(imageURL: url, filename: filename)
        case .wallhaven:
            guard let wallpaper = wallhavenStore.effectiveSelectedWallpaper else { return }
            wallhavenDetailInteraction.saveWallpaper(wallpaper)
        case .favorites:
            guard favoritesModuleStore.selectedRecord == favoritesDetailStore.currentRecord,
                  favoritesDetailStore.contentMode == .image,
                  favoritesDetailStore.hasResolvedSelectedImage,
                  let slot = favoritesDetailStore.selectedSlot,
                  let url = favoritesDetailStore.imageURL(for: slot) else { return }
            let source = favoritesModuleStore.selectedRecord.flatMap(FavoriteSource.source(for:))
            favoritesDetailInteraction.save(imageURL: url, filename: url.lastPathComponent, source: source)
        case .knitGallery:
            guard knitStore.detailContentMode == .image,
                  knitStore.hasResolvedSelectedImage,
                  let item = knitStore.selectedItem,
                  let slot = knitStore.selectedSlot else { return }
            knitDetailInteraction.save(item: item, slot: slot)
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
        case .knitGallery:
            guard let item = knitStore.selectedItem else { return }
            result = downloadStore.enqueueAlbumChoosingFolder(source: .knit(item))
        case .favorites:
            guard let record = favoritesModuleStore.selectedRecord else { return }
            switch FavoriteSource.source(for: record) {
            case .gallery:
                guard let item = GalleryFavoritesBridge.galleryItems(from: [record]).first else { return }
                result = downloadStore.enqueueAlbumChoosingFolder(source: .gallery(item))
            case .missKon:
                guard let item = MissKonFavoritesBridge.missKonItems(from: [record]).first else { return }
                result = downloadStore.enqueueAlbumChoosingFolder(source: .missKon(item))
            case .wallhaven, nil:
                return
            case .knit:
                guard let item = KnitFavoritesBridge.item(from: record) else { return }
                result = downloadStore.enqueueAlbumChoosingFolder(source: .knit(item))
            }
        case .localLibrary, .wallhaven:
            return
        }
        switch result {
        case .enqueued:
            // 下载开始即弹出管理窗口,让用户能看到进度与队列。
            WorkspaceDownloadsPresenter.show()
        case .duplicate:
            let alert = makeAppAlert(
                title: "该图集已在下载队列中",
                message: "同一下载任务正在排队或下载中。",
                style: .informational
            )
            presentAppAlert(alert, in: appModalHostWindow())
        case .cancelled, nil:
            break
        }
    }

    func saveCurrentVideo(for moduleID: WorkspaceModuleID) {
        switch moduleID {
        case .knitGallery:
            guard let item = knitStore.selectedItem,
                  let videoURL = knitStore.videoURL else { return }
            knitDetailInteraction.saveVideo(item: item, sourceURL: videoURL)
        case .favorites:
            guard favoritesModuleStore.selectedRecord == favoritesDetailStore.currentRecord else { return }
            favoritesDetailStore.saveVideoAsMP4()
        case .fourKHDGallery, .localLibrary, .missKon, .wallhaven:
            return
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
        case .favorites:
            favoritesDetailInteraction.resetZoom()
        case .knitGallery:
            knitDetailInteraction.resetZoom()
        }
    }

    func toggleFilmstrip() {
        filmstripVisibility.toggle()
    }
}
