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
    let localLibraryStore: LocalLibraryStore
    let favoritesStore: FavoritesStore
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
        localLibraryStore: LocalLibraryStore,
        favoritesStore: FavoritesStore,
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
        self.localLibraryStore = localLibraryStore
        self.favoritesStore = favoritesStore
        self.toolbarContext = toolbarContext
        self.downloadStore = downloadStore
        self.importRootFolderAction = importRootFolderAction
    }

    func importRootFolder() {
        importRootFolderAction()
    }
}
