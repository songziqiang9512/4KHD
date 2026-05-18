import Observation

@MainActor
@Observable
final class WorkspaceAppContext {
    let moduleRegistry: WorkspaceModuleRegistry
    let routeController: WorkspaceRouteController
    let detailPaneController: WorkspaceDetailPaneController
    let galleryStore: FourKHDGalleryStore
    let localLibraryStore: LocalLibraryStore
    let toolbarContext: WorkspaceToolbarContext
    @ObservationIgnored private let importRootFolderAction: () -> Void

    init(
        moduleRegistry: WorkspaceModuleRegistry,
        routeController: WorkspaceRouteController,
        detailPaneController: WorkspaceDetailPaneController,
        galleryStore: FourKHDGalleryStore,
        localLibraryStore: LocalLibraryStore,
        toolbarContext: WorkspaceToolbarContext,
        importRootFolderAction: @escaping () -> Void
    ) {
        self.moduleRegistry = moduleRegistry
        self.routeController = routeController
        self.detailPaneController = detailPaneController
        self.galleryStore = galleryStore
        self.localLibraryStore = localLibraryStore
        self.toolbarContext = toolbarContext
        self.importRootFolderAction = importRootFolderAction
    }

    func importRootFolder() {
        importRootFolderAction()
    }
}
