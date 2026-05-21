import AppKit

enum WorkspaceAppAssembly {
    @MainActor
    static func makeAppContext() -> WorkspaceAppContext {
        let fourKHDGalleryStore = FourKHDGalleryStore()
        let galleryPreferences = GalleryContentPreferences()
        let galleryDetailInteraction = GalleryDetailInteractionController()
        let localLibraryStore = LocalLibraryStore()
        let localPreferences = LocalLibraryContentPreferences()
        let localDetailInteraction = LocalDetailInteractionController()
        let filmstripVisibility = FilmstripVisibilityController()
        let detailPaneController = WorkspaceDetailPaneController()
        let importRootFolderAction = {
            guard let folderURL = LocalLibraryImportService.chooseFolder() else { return }
            localLibraryStore.importRootFolder(folderURL)
        }
        let moduleRegistry = makeModuleRegistry(
            fourKHDGalleryStore: fourKHDGalleryStore,
            galleryPreferences: galleryPreferences,
            galleryDetailInteraction: galleryDetailInteraction,
            localLibraryStore: localLibraryStore,
            localPreferences: localPreferences,
            localDetailInteraction: localDetailInteraction,
            filmstripVisibility: filmstripVisibility,
            importRootFolderAction: importRootFolderAction
        )
        let toolbarContext = WorkspaceToolbarContext(
            galleryStore: fourKHDGalleryStore,
            galleryPreferences: galleryPreferences,
            galleryDetailInteraction: galleryDetailInteraction,
            localLibraryStore: localLibraryStore,
            localPreferences: localPreferences,
            localDetailInteraction: localDetailInteraction,
            filmstripVisibility: filmstripVisibility,
            importRootFolderAction: importRootFolderAction
        )
        let routeController = WorkspaceRouteController(
            defaultRoute: moduleRegistry.defaultRoute(),
            normalizeRoute: { moduleRegistry.normalizedRoute($0) },
            applyRoute: { moduleRegistry.apply($0) }
        )

        return WorkspaceAppContext(
            moduleRegistry: moduleRegistry,
            routeController: routeController,
            detailPaneController: detailPaneController,
            galleryStore: fourKHDGalleryStore,
            localLibraryStore: localLibraryStore,
            toolbarContext: toolbarContext,
            importRootFolderAction: importRootFolderAction
        )
    }

    @MainActor
    private static func makeModuleRegistry(
        fourKHDGalleryStore: FourKHDGalleryStore,
        galleryPreferences: GalleryContentPreferences,
        galleryDetailInteraction: GalleryDetailInteractionController,
        localLibraryStore: LocalLibraryStore,
        localPreferences: LocalLibraryContentPreferences,
        localDetailInteraction: LocalDetailInteractionController,
        filmstripVisibility: FilmstripVisibilityController,
        importRootFolderAction: @escaping () -> Void
    ) -> WorkspaceModuleRegistry {
        return WorkspaceModuleRegistry(
            modules: [
                WorkspaceModuleDescriptor(
                    id: .localLibrary,
                    displayName: "LocalLibrary",
                    defaultRoute: {
                        WorkspaceRoute(moduleID: .localLibrary, itemID: LocalLibraryStore.allImagesFolderID)
                    },
                    makeContentController: { context in
                        LocalImageContentViewController(
                            localLibrary: localLibraryStore,
                            preferences: localPreferences,
                            detailPane: context.detailPaneController,
                            importRootFolderAction: importRootFolderAction
                        )
                    },
                    makeDetailController: { context in
                        LocalImageDetailViewController(
                            localLibrary: localLibraryStore,
                            immersive: context.immersive,
                            detailInteraction: localDetailInteraction,
                            filmstripVisibility: filmstripVisibility
                        )
                    },
                    normalizeRoute: { route in
                        if localLibraryStore.isAllImagesFolderID(route.itemID) {
                            return WorkspaceRoute(moduleID: .localLibrary, itemID: LocalLibraryStore.allImagesFolderID)
                        }
                        if let folder = localLibraryStore.findFolder(id: route.itemID) {
                            return WorkspaceRoute(moduleID: .localLibrary, itemID: folder.id)
                        }
                        return WorkspaceRoute(moduleID: .localLibrary, itemID: LocalLibraryStore.allImagesFolderID)
                    },
                    applyRoute: { route in
                        if localLibraryStore.isAllImagesFolderID(route.itemID) {
                            localLibraryStore.selectAllImages()
                            return
                        }
                        if let folder = localLibraryStore.findFolder(id: route.itemID) {
                            localLibraryStore.selectFolder(folder)
                        }
                    },
                    bootstrap: {}
                ),
                WorkspaceModuleDescriptor(
                    id: .fourKHDGallery,
                    displayName: "4KHDGallery",
                    defaultRoute: {
                        WorkspaceRoute(moduleID: .fourKHDGallery, itemID: GallerySection.latest.rawValue)
                    },
                    makeContentController: { context in
                        GalleryContentViewController(
                            library: fourKHDGalleryStore,
                            preferences: galleryPreferences,
                            detailPane: context.detailPaneController
                        )
                    },
                    makeDetailController: { context in
                        GalleryImageDetailViewController(
                            library: fourKHDGalleryStore,
                            immersive: context.immersive,
                            detailPane: context.detailPaneController,
                            detailInteraction: galleryDetailInteraction,
                            filmstripVisibility: filmstripVisibility
                        )
                    },
                    normalizeRoute: { route in
                        guard let section = GallerySection(rawValue: route.itemID) else {
                            return WorkspaceRoute(moduleID: .fourKHDGallery, itemID: GallerySection.latest.rawValue)
                        }
                        return WorkspaceRoute(moduleID: .fourKHDGallery, itemID: section.rawValue)
                    },
                    applyRoute: { route in
                        guard let section = GallerySection(rawValue: route.itemID) else { return }
                        if fourKHDGalleryStore.section != section {
                            fourKHDGalleryStore.section = section
                        }
                    },
                    bootstrap: {
                        fourKHDGalleryStore.refreshFromNetwork()
                    }
                )
            ]
        )
    }
}
