import AppKit

enum WorkspaceAppAssembly {
    @MainActor
    static func makeAppContext() -> WorkspaceAppContext {
        let favoritesStore = FavoritesStore()
        let fourKHDGalleryStore = FourKHDGalleryStore(favorites: favoritesStore)
        let galleryPreferences = GalleryContentPreferences()
        let galleryDetailInteraction = GalleryDetailInteractionController()
        let missKonFeedStore = MissKonFeedStore(favoritesStore: favoritesStore)
        let missKonDetailStore = MissKonDetailStore()
        let missKonStore = MissKonGalleryStore(feed: missKonFeedStore, detail: missKonDetailStore, favorites: favoritesStore)
        let missKonPreferences = MissKonContentPreferences()
        let missKonDetailInteraction = MissKonDetailInteractionController()
        let wallhavenAccountStore = WallhavenAccountStore()
        let wallhavenPreferences = WallhavenContentPreferences()
        let wallhavenFeedStore = WallhavenFeedStore(accountStore: wallhavenAccountStore, preferences: wallhavenPreferences, favoritesStore: favoritesStore)
        let wallhavenStore = WallhavenGalleryStore(feed: wallhavenFeedStore, favorites: favoritesStore)
        favoritesStore.onFavoritesChanged = {
            [weak fourKHDGalleryStore, weak missKonStore, weak wallhavenStore] in
            fourKHDGalleryStore?.refreshFavoritesIfNeeded()
            missKonStore?.refreshFavoritesIfNeeded()
            wallhavenStore?.refreshFavoritesIfNeeded()
        }
        let wallhavenDetailInteraction = WallhavenDetailInteractionController()
        let localLibraryStore = LocalLibraryStore()
        let localPreferences = LocalLibraryContentPreferences()
        let localDetailInteraction = LocalDetailInteractionController()
        let filmstripVisibility = FilmstripVisibilityController()
        let detailPaneController = WorkspaceDetailPaneController()
        let downloadStore = DownloadStore()
        let importRootFolderAction = {
            guard let folderURL = LocalLibraryImportService.chooseFolder() else { return }
            localLibraryStore.importRootFolder(folderURL)
        }
        let moduleRegistry = makeModuleRegistry(
            fourKHDGalleryStore: fourKHDGalleryStore,
            galleryPreferences: galleryPreferences,
            galleryDetailInteraction: galleryDetailInteraction,
            missKonStore: missKonStore,
            missKonPreferences: missKonPreferences,
            missKonDetailInteraction: missKonDetailInteraction,
            wallhavenStore: wallhavenStore,
            wallhavenPreferences: wallhavenPreferences,
            wallhavenDetailInteraction: wallhavenDetailInteraction,
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
            missKonStore: missKonStore,
            missKonPreferences: missKonPreferences,
            missKonDetailInteraction: missKonDetailInteraction,
            wallhavenStore: wallhavenStore,
            wallhavenPreferences: wallhavenPreferences,
            wallhavenDetailInteraction: wallhavenDetailInteraction,
            localLibraryStore: localLibraryStore,
            localPreferences: localPreferences,
            localDetailInteraction: localDetailInteraction,
            filmstripVisibility: filmstripVisibility,
            detailPaneController: detailPaneController,
            downloadStore: downloadStore,
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
            missKonStore: missKonStore,
            wallhavenStore: wallhavenStore,
            localLibraryStore: localLibraryStore,
            favoritesStore: favoritesStore,
            toolbarContext: toolbarContext,
            downloadStore: downloadStore,
            importRootFolderAction: importRootFolderAction
        )
    }

    @MainActor
    private static func makeModuleRegistry(
        fourKHDGalleryStore: FourKHDGalleryStore,
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
                        fourKHDGalleryStore.bootstrapIfNeeded()
                    }
                ),
                WorkspaceModuleDescriptor(
                    id: .missKon,
                    displayName: "MissKon",
                    defaultRoute: {
                        WorkspaceRoute(moduleID: .missKon, itemID: MissKonSection.latest.rawValue)
                    },
                    makeContentController: { context in
                        MissKonContentViewController(
                            library: missKonStore,
                            preferences: missKonPreferences,
                            detailPane: context.detailPaneController
                        )
                    },
                    makeDetailController: { context in
                        MissKonImageDetailViewController(
                            library: missKonStore,
                            immersive: context.immersive,
                            detailPane: context.detailPaneController,
                            detailInteraction: missKonDetailInteraction,
                            filmstripVisibility: filmstripVisibility
                        )
                    },
                    normalizeRoute: { route in
                        guard let section = MissKonSection(rawValue: route.itemID) else {
                            return WorkspaceRoute(moduleID: .missKon, itemID: MissKonSection.latest.rawValue)
                        }
                        return WorkspaceRoute(moduleID: .missKon, itemID: section.rawValue)
                    },
                    applyRoute: { route in
                        guard let section = MissKonSection(rawValue: route.itemID) else { return }
                        if missKonStore.section != section {
                            missKonStore.section = section
                        }
                    },
                    bootstrap: {
                        missKonStore.bootstrapIfNeeded()
                    }
                ),
                WorkspaceModuleDescriptor(
                    id: .wallhaven,
                    displayName: "Wallhaven",
                    defaultRoute: {
                        WorkspaceRoute(moduleID: .wallhaven, itemID: WallhavenSection.browse.rawValue)
                    },
                    makeContentController: { context in
                        WallhavenContentViewController(
                            library: wallhavenStore,
                            preferences: wallhavenPreferences,
                            detailPane: context.detailPaneController
                        )
                    },
                    makeDetailController: { context in
                        WallhavenImageDetailViewController(
                            library: wallhavenStore,
                            immersive: context.immersive,
                            detailPane: context.detailPaneController,
                            detailInteraction: wallhavenDetailInteraction
                        )
                    },
                    normalizeRoute: { route in
                        guard let section = WallhavenSection(rawValue: route.itemID) else {
                            return WorkspaceRoute(moduleID: .wallhaven, itemID: WallhavenSection.browse.rawValue)
                        }
                        return WorkspaceRoute(moduleID: .wallhaven, itemID: section.rawValue)
                    },
                    applyRoute: { route in
                        guard let section = WallhavenSection(rawValue: route.itemID) else { return }
                        if wallhavenStore.section != section {
                            wallhavenStore.setSection(section)
                        }
                    },
                    bootstrap: {
                        wallhavenStore.bootstrapIfNeeded()
                    }
                )
            ]
        )
    }
}
