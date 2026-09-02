import Observation

@MainActor
@Observable
final class WorkspaceAppContext {
    let moduleRegistry: WorkspaceModuleRegistry
    let routeController: WorkspaceRouteController
    let detailPaneController: WorkspaceDetailPaneController
    let galleryStore: FourKHDGalleryStore
    let missKonStore: MissKonGalleryStore
    let wallhavenStore: WallhavenGalleryStore
    let knitStore: KnitGalleryStore
    let mrdsStore: MrdsGalleryStore
    let quanjiStore: OnlineVideoGalleryStore
    let pornyStore: OnlineVideoGalleryStore
    let tangxinStore: OnlineVideoGalleryStore
    let taiavStore: OnlineVideoGalleryStore
    let localLibraryStore: LocalLibraryStore
    let favoritesStore: FavoritesStore
    let favoritesModuleStore: FavoritesModuleStore
    let favoritesDetailStore: FavoritesDetailStore
    let favoritesPreferences: FavoritesContentPreferences
    let toolbarContext: WorkspaceToolbarContext
    let downloadStore: DownloadStore
    @ObservationIgnored private let importRootFolderAction: () -> Void

    init(
        moduleRegistry: WorkspaceModuleRegistry,
        routeController: WorkspaceRouteController,
        detailPaneController: WorkspaceDetailPaneController,
        galleryStore: FourKHDGalleryStore,
        missKonStore: MissKonGalleryStore,
        wallhavenStore: WallhavenGalleryStore,
        knitStore: KnitGalleryStore,
        mrdsStore: MrdsGalleryStore,
        quanjiStore: OnlineVideoGalleryStore,
        pornyStore: OnlineVideoGalleryStore,
        tangxinStore: OnlineVideoGalleryStore,
        taiavStore: OnlineVideoGalleryStore,
        localLibraryStore: LocalLibraryStore,
        favoritesStore: FavoritesStore,
        favoritesModuleStore: FavoritesModuleStore,
        favoritesDetailStore: FavoritesDetailStore,
        favoritesPreferences: FavoritesContentPreferences,
        toolbarContext: WorkspaceToolbarContext,
        downloadStore: DownloadStore,
        importRootFolderAction: @escaping () -> Void
    ) {
        self.moduleRegistry = moduleRegistry
        self.routeController = routeController
        self.detailPaneController = detailPaneController
        self.galleryStore = galleryStore
        self.missKonStore = missKonStore
        self.wallhavenStore = wallhavenStore
        self.knitStore = knitStore
        self.mrdsStore = mrdsStore
        self.quanjiStore = quanjiStore
        self.pornyStore = pornyStore
        self.tangxinStore = tangxinStore
        self.taiavStore = taiavStore
        self.localLibraryStore = localLibraryStore
        self.favoritesStore = favoritesStore
        self.favoritesModuleStore = favoritesModuleStore
        self.favoritesDetailStore = favoritesDetailStore
        self.favoritesPreferences = favoritesPreferences
        self.toolbarContext = toolbarContext
        self.downloadStore = downloadStore
        self.importRootFolderAction = importRootFolderAction
    }

    func importRootFolder() {
        importRootFolderAction()
    }
}
