import AppKit
import Foundation

enum WorkspaceToolbarSnapshot {
    case gallery(GallerySnapshot)
    case local(LocalSnapshot)
    case missKon(MissKonSnapshot)
    case wallhaven(WallhavenSnapshot)
    case favorites(FavoritesSnapshot)
    case knit(KnitSnapshot)
    case mrds(MrdsSnapshot)
    case quanji(VideoFeedSnapshot)
    case porny(VideoFeedSnapshot)
    case tangxin(VideoFeedSnapshot)

    struct GallerySnapshot {
        let searchText: String
        let layout: GalleryContentLayout
        let locationTitle: String
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
        let locationTitle: String
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
        let locationTitle: String
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
        let locationTitle: String
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

    struct MrdsSnapshot {
        let searchText: String
        let layout: MrdsContentLayout
        let locationTitle: String
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

    struct VideoFeedSnapshot {
        let searchText: String
        let layout: OnlineVideoContentLayout
        let locationTitle: String
        let isRefreshing: Bool
        let canFavorite: Bool
        let isFavorite: Bool
        let canIncreaseGridColumns: Bool
        let canDecreaseGridColumns: Bool
        let canSelectPreviousImage: Bool
        let canSelectNextImage: Bool
        let canSaveVideo: Bool
        let canShare: Bool
        let showsDirectoryListing: Bool
        let searchPlaceholder: String
    }

    struct LocalSnapshot {
        let searchText: String
        let layout: LocalContentLayout
        let sortField: LocalImageSortField
        let sortDirection: LocalImageSortDirection
        let locationTitle: String
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
        let locationTitle: String
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
        let locationTitle: String
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
        case let .gallery(s):
            CommonFields(
                moduleName: "4KHD", locationTitle: s.locationTitle, searchText: s.searchText,
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
        case let .local(s):
            CommonFields(
                moduleName: "本地图片", locationTitle: s.locationTitle, searchText: s.searchText,
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
        case let .missKon(s):
            CommonFields(
                moduleName: "MissKon", locationTitle: s.locationTitle, searchText: s.searchText,
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
        case let .wallhaven(s):
            CommonFields(
                moduleName: "Wallhaven", locationTitle: s.locationTitle, searchText: s.searchText,
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
        case let .favorites(s):
            CommonFields(
                moduleName: "我的收藏", locationTitle: s.locationTitle, searchText: s.searchText,
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
        case let .knit(s):
            CommonFields(
                moduleName: "爱妹子", locationTitle: s.locationTitle, searchText: s.searchText,
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
        case let .mrds(s):
            CommonFields(
                moduleName: "每日大赛", locationTitle: s.locationTitle, searchText: s.searchText,
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
        case let .quanji(s):
            Self.videoFields(s, moduleName: "木瓜视频")
        case let .porny(s):
            Self.videoFields(s, moduleName: "91PORNY")
        case let .tangxin(s):
            Self.videoFields(s, moduleName: "糖心Vlog")
        }
    }

    private static func videoFields(_ s: VideoFeedSnapshot, moduleName: String) -> CommonFields {
        CommonFields(
            moduleName: moduleName, locationTitle: s.locationTitle, searchText: s.searchText,
            isRefreshing: s.isRefreshing,
            canFavorite: s.canFavorite, isFavorite: s.isFavorite,
            canIncreaseGridColumns: s.canIncreaseGridColumns,
            canDecreaseGridColumns: s.canDecreaseGridColumns,
            canSelectPreviousImage: s.canSelectPreviousImage,
            canSelectNextImage: s.canSelectNextImage,
            canSaveImage: false, canSaveAlbum: false, canSaveVideo: s.canSaveVideo,
            canResetZoom: false,
            canShare: s.canShare, canUseFilmstrip: false,
            isFilmstripPresented: false,
            hasSelection: s.canShare
        )
    }

    var isListLayout: Bool {
        switch self {
        case let .gallery(snapshot):
            snapshot.layout == .list
        case let .local(snapshot):
            snapshot.layout == .list
        case let .missKon(snapshot):
            snapshot.layout == .list
        case let .wallhaven(snapshot):
            snapshot.layout == .list
        case let .favorites(snapshot):
            snapshot.layout == .list
        case let .knit(snapshot):
            snapshot.layout == .list
        case let .mrds(snapshot):
            snapshot.layout == .list
        case let .quanji(snapshot), let .porny(snapshot), let .tangxin(snapshot):
            snapshot.layout == .list
        }
    }
}

enum WorkspaceCurrentReference {
    case web(URL)
    case file(URL)

    var url: URL {
        switch self {
        case let .web(url), let .file(url):
            return url
        }
    }

    var fileURL: URL? {
        switch self {
        case .web:
            return nil
        case let .file(url):
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
        case let .web(url):
            let urlString = url.absoluteString
            pasteboard.setString(urlString, forType: .URL)
            pasteboard.setString(urlString, forType: .string)
        case let .file(url):
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
    private let mrdsStore: MrdsGalleryStore
    private let mrdsPreferences: MrdsContentPreferences
    private let mrdsDetailInteraction: MrdsDetailInteractionController
    private let quanjiStore: OnlineVideoGalleryStore
    private let quanjiPreferences: OnlineVideoContentPreferences
    private let quanjiDetailInteraction: OnlineVideoDetailInteractionController
    private let pornyStore: OnlineVideoGalleryStore
    private let pornyPreferences: OnlineVideoContentPreferences
    private let pornyDetailInteraction: OnlineVideoDetailInteractionController
    private let tangxinStore: OnlineVideoGalleryStore
    private let tangxinPreferences: OnlineVideoContentPreferences
    private let tangxinDetailInteraction: OnlineVideoDetailInteractionController
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
        mrdsStore: MrdsGalleryStore,
        mrdsPreferences: MrdsContentPreferences,
        mrdsDetailInteraction: MrdsDetailInteractionController,
        quanjiStore: OnlineVideoGalleryStore,
        quanjiPreferences: OnlineVideoContentPreferences,
        quanjiDetailInteraction: OnlineVideoDetailInteractionController,
        pornyStore: OnlineVideoGalleryStore,
        pornyPreferences: OnlineVideoContentPreferences,
        pornyDetailInteraction: OnlineVideoDetailInteractionController,
        tangxinStore: OnlineVideoGalleryStore,
        tangxinPreferences: OnlineVideoContentPreferences,
        tangxinDetailInteraction: OnlineVideoDetailInteractionController,
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
        self.mrdsStore = mrdsStore
        self.mrdsPreferences = mrdsPreferences
        self.mrdsDetailInteraction = mrdsDetailInteraction
        self.quanjiStore = quanjiStore
        self.quanjiPreferences = quanjiPreferences
        self.quanjiDetailInteraction = quanjiDetailInteraction
        self.pornyStore = pornyStore
        self.pornyPreferences = pornyPreferences
        self.pornyDetailInteraction = pornyDetailInteraction
        self.tangxinStore = tangxinStore
        self.tangxinPreferences = tangxinPreferences
        self.tangxinDetailInteraction = tangxinDetailInteraction
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
                    locationTitle: galleryStore.section == .latest ? "4KHD" : galleryStore.section.title,
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
                    locationTitle: localLibraryStore.selectedFolderID == LocalLibraryStore.allImagesFolderID
                        ? "本地图片"
                        : (localLibraryStore.selectedFolder?.title ?? "本地图片"),
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
                    locationTitle: missKonStore.section == .latest ? "MissKon" : missKonStore.section.title,
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
                    locationTitle: wallhavenLocationTitle(store: wallhavenStore),
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
            let canSaveAlbum = source == .gallery || source == .missKon || source == .knit || source == .mrds
            let playsFromFeed = selectedRecord
                .flatMap { FavoriteSourceAdapterRegistry.shared.adapter(for: $0)?.playsFromFeed } == true
            let detailMatchesSelection = selectedRecord != nil
                && favoritesDetailStore.currentRecord == selectedRecord
            let canAdjustGridColumns = favoritesPreferences.layout == .grid
                && !detailPaneController.isPresented
            let canSelectPrevious: Bool
            let canSelectNext: Bool
            if let selectedRecord,
               playsFromFeed || (detailMatchesSelection && favoritesDetailStore.navigationMode == .sourceRecords)
            {
                canSelectPrevious = favoritesModuleStore.canStepSourceRecord(from: selectedRecord, delta: -1)
                canSelectNext = favoritesModuleStore.canStepSourceRecord(from: selectedRecord, delta: 1)
            } else {
                canSelectPrevious = detailMatchesSelection && favoritesDetailStore.canStepBackward
                canSelectNext = detailMatchesSelection && favoritesDetailStore.canStepForward
            }
            let canSaveFeedVideo = selectedRecord.flatMap { record -> Bool? in
                let adapter = FavoriteSourceAdapterRegistry.shared.adapter(for: record)
                guard adapter?.playsFromFeed == true else { return false }
                return adapter?.videoActions?.canSaveAsMP4 == true
            } ?? false
            return .favorites(
                .init(
                    searchText: favoritesModuleStore.searchText,
                    layout: favoritesPreferences.layout,
                    locationTitle: favoritesModuleStore.filter == .all
                        ? "我的收藏"
                        : favoritesModuleStore.filter.title,
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
                    canSaveVideo: canSaveFeedVideo
                        || (detailMatchesSelection && favoritesDetailStore.canSaveVideo),
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
                    locationTitle: knitStore.filter == .all ? "爱妹子" : knitStore.filter.title,
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
        case .mrdsGallery:
            let item = mrdsStore.selectedItem
            let canAdjust = mrdsPreferences.layout == .grid && !detailPaneController.isPresented
            return .mrds(
                .init(
                    searchText: mrdsStore.searchText,
                    layout: mrdsPreferences.layout,
                    locationTitle: mrdsStore.filter == .latest ? "每日大赛" : mrdsStore.filter.title,
                    isRefreshing: mrdsStore.isRefreshingList,
                    canFavorite: item != nil,
                    isFavorite: item.map { mrdsStore.isFavorite($0) } ?? false,
                    canIncreaseGridColumns: canAdjust && mrdsPreferences.canIncreaseGridColumns,
                    canDecreaseGridColumns: canAdjust && mrdsPreferences.canDecreaseGridColumns,
                    canSelectPreviousImage: mrdsStore.canStepDetailBackward,
                    canSelectNextImage: mrdsStore.canStepDetailForward,
                    canSaveImage: mrdsStore.detailContentMode == .image
                        && item != nil
                        && mrdsStore.hasResolvedSelectedImage,
                    canSaveAlbum: item != nil,
                    canSaveVideo: item != nil && mrdsStore.videoURL != nil,
                    canResetZoom: mrdsStore.detailContentMode == .image
                        && mrdsStore.selectedSlot != nil,
                    canShare: item != nil,
                    isFilmstripPresented: filmstripVisibility.isPresented
                )
            )
        case .quanjiGallery:
            return .quanji(videoFeedSnapshot(store: quanjiStore, preferences: quanjiPreferences))
        case .pornyGallery:
            return .porny(videoFeedSnapshot(store: pornyStore, preferences: pornyPreferences))
        case .tangxinGallery:
            return .tangxin(videoFeedSnapshot(store: tangxinStore, preferences: tangxinPreferences))
        }
    }

    private func videoFeedSnapshot(
        store: OnlineVideoGalleryStore,
        preferences: OnlineVideoContentPreferences
    ) -> WorkspaceToolbarSnapshot.VideoFeedSnapshot {
        let item = store.selectedItem
        let isPlayable = item.map { !$0.isDirectoryEntry } ?? false
        let canAdjust = preferences.layout == .grid
            && !detailPaneController.isPresented
            && !store.showsDirectoryListing
        return .init(
            searchText: store.searchText,
            layout: preferences.layout,
            locationTitle: store.locationTitle,
            isRefreshing: store.isRefreshingList,
            canFavorite: isPlayable,
            isFavorite: item.map { store.isFavorite($0) } ?? false,
            canIncreaseGridColumns: canAdjust && preferences.canIncreaseGridColumns,
            canDecreaseGridColumns: canAdjust && preferences.canDecreaseGridColumns,
            canSelectPreviousImage: store.canStepSelectionBackward,
            canSelectNextImage: store.canStepSelectionForward,
            canSaveVideo: isPlayable,
            canShare: item != nil,
            showsDirectoryListing: store.showsDirectoryListing,
            searchPlaceholder: videoSearchPlaceholder(store: store)
        )
    }

    private func wallhavenLocationTitle(store: WallhavenGalleryStore) -> String {
        if store.isBrowsingUploader, let username = store.uploaderUsername, !username.isEmpty {
            return username
        }
        if let query = store.activeSearchQuery, !query.isEmpty {
            return query
        }
        if store.category != .all {
            return store.category.title
        }
        return "Wallhaven"
    }

    private func videoSearchPlaceholder(store: OnlineVideoGalleryStore) -> String {
        if store.showsDirectoryListing {
            return store.filter == TangxinSection.authors.rawValue ? "筛选作者" : "筛选分类"
        }
        if store.policySource == .tangxin {
            return "搜索视频"
        }
        return "搜索 \(store.sourceTitle)"
    }

    private func videoStore(for moduleID: WorkspaceModuleID) -> OnlineVideoGalleryStore? {
        switch moduleID {
        case .quanjiGallery: quanjiStore
        case .pornyGallery: pornyStore
        case .tangxinGallery: tangxinStore
        default: nil
        }
    }

    private func videoPreferences(for moduleID: WorkspaceModuleID) -> OnlineVideoContentPreferences? {
        switch moduleID {
        case .quanjiGallery: quanjiPreferences
        case .pornyGallery: pornyPreferences
        case .tangxinGallery: tangxinPreferences
        default: nil
        }
    }

    private func videoInteraction(for moduleID: WorkspaceModuleID) -> OnlineVideoDetailInteractionController? {
        switch moduleID {
        case .quanjiGallery: quanjiDetailInteraction
        case .pornyGallery: pornyDetailInteraction
        case .tangxinGallery: tangxinDetailInteraction
        default: nil
        }
    }

    func setSearchText(_ text: String, for moduleID: WorkspaceModuleID) {
        switch moduleID {
        case .fourKHDGallery:
            galleryStore.searchText = text
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               galleryStore.activeSearchQuery != nil
            {
                galleryStore.clearSearch()
            }
        case .localLibrary:
            localPreferences.searchText = text
        case .missKon:
            missKonStore.feed.searchText = text
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               missKonStore.activeSearchQuery != nil
            {
                missKonStore.clearSearch()
            }
        case .wallhaven:
            wallhavenStore.setSearchText(text)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               wallhavenStore.activeSearchQuery != nil
            {
                wallhavenStore.clearSearch()
            }
        case .favorites:
            favoritesModuleStore.searchText = text
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               favoritesModuleStore.activeSearchQuery != nil
            {
                favoritesModuleStore.clearSearch()
            }
        case .knitGallery:
            knitStore.searchText = text
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               knitStore.activeSearchQuery != nil
            {
                knitStore.clearSearch()
            }
        case .mrdsGallery:
            mrdsStore.searchText = text
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               mrdsStore.activeSearchQuery != nil
            {
                mrdsStore.clearSearch()
            }
        case .quanjiGallery, .pornyGallery, .tangxinGallery:
            guard let store = videoStore(for: moduleID) else { return }
            store.searchText = text
            if store.showsDirectoryListing {
                let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if query.isEmpty {
                    store.clearSearch()
                } else {
                    store.submitSearch()
                }
                return
            }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               store.activeSearchQuery != nil
            {
                store.clearSearch()
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
        case .mrdsGallery:
            mrdsPreferences.layout = isList ? .list : .grid
        case .quanjiGallery, .pornyGallery, .tangxinGallery:
            videoPreferences(for: moduleID)?.layout = isList ? .list : .grid
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
        case .mrdsGallery:
            guard mrdsPreferences.layout == .grid, !detailPaneController.isPresented else { return }
            mrdsPreferences.adjustGridColumns(delta: delta)
        case .quanjiGallery, .pornyGallery, .tangxinGallery:
            guard let preferences = videoPreferences(for: moduleID),
                  preferences.layout == .grid,
                  !detailPaneController.isPresented else { return }
            preferences.adjustGridColumns(delta: delta)
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
        case .mrdsGallery:
            mrdsStore.submitSearch()
        case .quanjiGallery, .pornyGallery, .tangxinGallery:
            videoStore(for: moduleID)?.submitSearch()
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
        case .mrdsGallery:
            mrdsStore.refreshFromNetwork()
        case .quanjiGallery, .pornyGallery, .tangxinGallery:
            videoStore(for: moduleID)?.refreshFromNetwork()
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
        case .mrdsGallery:
            return mrdsStore.selectedItem.map { [$0.detailURL] } ?? []
        case .quanjiGallery, .pornyGallery, .tangxinGallery:
            return videoStore(for: moduleID)?.selectedItem.map { [$0.detailURL] } ?? []
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
        case .mrdsGallery:
            return mrdsStore.selectedItem.map { .web($0.detailURL) }
        case .quanjiGallery, .pornyGallery, .tangxinGallery:
            return videoStore(for: moduleID)?.selectedItem.map { .web($0.detailURL) }
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
                case .mrdsGallery:
                    guard let item = mrdsStore.selectedItem else { return }
                    try await mrdsStore.toggleFavorite(for: item)
                case .quanjiGallery, .pornyGallery, .tangxinGallery:
                    guard let store = videoStore(for: moduleID),
                          let item = store.selectedItem else { return }
                    try await store.toggleFavorite(for: item)
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
        case .mrdsGallery:
            mrdsStore.stepImage(delta)
        case .quanjiGallery, .pornyGallery, .tangxinGallery:
            videoStore(for: moduleID)?.stepSelection(delta)
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
        case .mrdsGallery:
            guard mrdsStore.detailContentMode == .image,
                  mrdsStore.hasResolvedSelectedImage,
                  let item = mrdsStore.selectedItem,
                  let slot = mrdsStore.selectedSlot else { return }
            mrdsDetailInteraction.save(item: item, slot: slot)
        case .quanjiGallery, .pornyGallery, .tangxinGallery:
            return
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
        case .mrdsGallery:
            guard let item = mrdsStore.selectedItem else { return }
            result = downloadStore.enqueueAlbumChoosingFolder(source: .mrds(item))
        case .favorites:
            guard let record = favoritesModuleStore.selectedRecord else { return }
            switch FavoriteSource.source(for: record) {
            case .gallery:
                guard let item = GalleryFavoritesBridge.galleryItems(from: [record]).first else { return }
                result = downloadStore.enqueueAlbumChoosingFolder(source: .gallery(item))
            case .missKon:
                guard let item = MissKonFavoritesBridge.missKonItems(from: [record]).first else { return }
                result = downloadStore.enqueueAlbumChoosingFolder(source: .missKon(item))
            case .wallhaven, .quanji, .porny, .tangxin, nil:
                return
            case .knit:
                guard let item = KnitFavoritesBridge.item(from: record) else { return }
                result = downloadStore.enqueueAlbumChoosingFolder(source: .knit(item))
            case .mrds:
                guard let item = MrdsFavoritesBridge.item(from: record) else { return }
                result = downloadStore.enqueueAlbumChoosingFolder(source: .mrds(item))
            }
        case .localLibrary, .wallhaven, .quanjiGallery, .pornyGallery, .tangxinGallery:
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
            guard let record = favoritesModuleStore.selectedRecord,
                  let adapter = FavoriteSourceAdapterRegistry.shared.adapter(for: record)
            else { return }
            if adapter.playsFromFeed {
                guard let actions = adapter.videoActions, actions.canSaveAsMP4 else { return }
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        let url = try await adapter.resolvePlayableVideoURL(for: record)
                        actions.saveAsMP4(record, url)
                    } catch is CancellationError {
                        return
                    } catch {
                        let alert = makeAppAlert(
                            title: "无法下载视频",
                            message: error.localizedDescription,
                            style: .warning
                        )
                        presentAppAlert(alert, in: appModalHostWindow())
                    }
                }
                return
            }
            guard favoritesDetailStore.currentRecord == record else { return }
            favoritesDetailStore.saveVideoAsMP4()
        case .mrdsGallery:
            guard let item = mrdsStore.selectedItem,
                  let videoURL = mrdsStore.videoURL else { return }
            mrdsDetailInteraction.saveVideo(item: item, sourceURL: videoURL)
        case .quanjiGallery, .pornyGallery, .tangxinGallery:
            guard let store = videoStore(for: moduleID),
                  let interaction = videoInteraction(for: moduleID),
                  let item = store.selectedItem else { return }
            Task { [weak self] in
                guard let self else { return }
                do {
                    let url = try await store.resolveVideoURL(for: item)
                    interaction.saveVideo(item: item, sourceURL: url)
                } catch is CancellationError {
                    return
                } catch {
                    let alert = makeAppAlert(
                        title: "无法下载视频",
                        message: error.localizedDescription,
                        style: .warning
                    )
                    presentAppAlert(alert, in: appModalHostWindow())
                }
            }
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
        case .mrdsGallery:
            mrdsDetailInteraction.resetZoom()
        case .quanjiGallery, .pornyGallery, .tangxinGallery:
            return
        }
    }

    func toggleFilmstrip() {
        filmstripVisibility.toggle()
    }
}
