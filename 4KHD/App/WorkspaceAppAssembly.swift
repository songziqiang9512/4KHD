import AppKit

enum WorkspaceAppAssembly {
    @MainActor
    static func makeAppContext() -> WorkspaceAppContext {
        configureFavoriteSourceAdapters()
        let favoritesStore = FavoritesStore()
        let favoritesModuleStore = FavoritesModuleStore(favoritesStore: favoritesStore)
        let favoritesPreferences = FavoritesContentPreferences()
        let favoritesDetailStore = FavoritesDetailStore()
        let favoritesDetailInteraction = FavoritesDetailInteractionController()
        let fourKHDGalleryStore = FourKHDGalleryStore(favorites: favoritesStore)
        let galleryPreferences = GalleryContentPreferences()
        let galleryDetailInteraction = GalleryDetailInteractionController()
        let missKonFeedStore = MissKonFeedStore()
        let missKonDetailStore = MissKonDetailStore()
        let missKonStore = MissKonGalleryStore(feed: missKonFeedStore, detail: missKonDetailStore, favorites: favoritesStore)
        let missKonPreferences = MissKonContentPreferences()
        let missKonDetailInteraction = MissKonDetailInteractionController()
        let wallhavenAccountStore = WallhavenAccountStore()
        let wallhavenPreferences = WallhavenContentPreferences()
        let wallhavenFeedStore = WallhavenFeedStore(accountStore: wallhavenAccountStore, preferences: wallhavenPreferences)
        let wallhavenStore = WallhavenGalleryStore(feed: wallhavenFeedStore, favorites: favoritesStore)
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
            favoritesModuleStore: favoritesModuleStore,
            favoritesPreferences: favoritesPreferences,
            favoritesDetailStore: favoritesDetailStore,
            favoritesDetailInteraction: favoritesDetailInteraction,
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
            favoritesModuleStore: favoritesModuleStore,
            favoritesPreferences: favoritesPreferences,
            favoritesDetailStore: favoritesDetailStore,
            favoritesDetailInteraction: favoritesDetailInteraction,
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
            favoritesModuleStore: favoritesModuleStore,
            favoritesPreferences: favoritesPreferences,
            toolbarContext: toolbarContext,
            downloadStore: downloadStore,
            importRootFolderAction: importRootFolderAction
        )
    }

    @MainActor
    private static func configureFavoriteSourceAdapters() {
        FavoriteSourceAdapterRegistry.shared.replaceAdapters([
            FavoriteSourceAdapter(
                source: .gallery,
                detailContent: { record in
                    guard let item = GalleryFavoritesBridge.galleryItems(from: [record]).first else { return nil }
                    return .paged(pageURLs: item.pageURLs, estimatedImageCount: item.imageCount)
                },
                resolvePage: { url in
                    let page = try await DetailPageHTMLResolver.resolve(pageURL: url)
                    return FavoriteResolvedImagePage(
                        imageURLs: page.imageURLs,
                        pageURLs: page.pageURLs,
                        recommendations: page.recommendations
                    )
                },
                configureImageRequest: GalleryRequestFactory.configureImageRequest
            ),
            FavoriteSourceAdapter(
                source: .missKon,
                detailContent: { record in
                    guard let item = MissKonFavoritesBridge.missKonItems(from: [record]).first else { return nil }
                    return .paged(pageURLs: item.pageURLs, estimatedImageCount: item.imageCount)
                },
                resolvePage: { url in
                    let page = try await MissKonDetailResolver.resolve(pageURL: url)
                    return FavoriteResolvedImagePage(
                        imageURLs: page.imageURLs,
                        pageURLs: page.pageURLs,
                        recommendations: page.recommendations
                    )
                },
                configureImageRequest: MissKonRequestFactory.configureImageRequest
            ),
            FavoriteSourceAdapter(
                source: .wallhaven,
                detailContent: { record in
                    guard let wallpaper = WallhavenFavoritesBridge.wallpapers(from: [record]).first else { return nil }
                    return .singleImage(wallpaper.cardCoverUrl)
                },
                resolvePage: { _ in throw URLError(.unsupportedURL) },
                configureImageRequest: WallhavenRequestFactory.configureImageRequest
            ),
        ])
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
        favoritesModuleStore: FavoritesModuleStore,
        favoritesPreferences: FavoritesContentPreferences,
        favoritesDetailStore: FavoritesDetailStore,
        favoritesDetailInteraction: FavoritesDetailInteractionController,
        filmstripVisibility: FilmstripVisibilityController,
        importRootFolderAction: @escaping () -> Void
    ) -> WorkspaceModuleRegistry {
        return WorkspaceModuleRegistry(
            modules: [
                WorkspaceModuleDescriptor(
                    id: .localLibrary,
                    displayName: "LocalLibrary",
                    presentation: WorkspaceModulePresentationProfile(
                        showsGridColumns: true, showsLocalSort: true, showsImportFolder: true,
                        showsFavorite: false, showsOnlineSave: false, showsWallhavenControls: false,
                        showsFavoritesFilter: false, filmstripAvailability: .selection,
                        refreshRequiresSelection: true, detailActions: .localFile
                    ),
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
                    presentation: WorkspaceModulePresentationProfile(
                        showsGridColumns: true, showsLocalSort: false, showsImportFolder: false,
                        showsFavorite: true, showsOnlineSave: true, showsWallhavenControls: false,
                        showsFavoritesFilter: false, filmstripAvailability: .detail,
                        refreshRequiresSelection: false, detailActions: .none
                    ),
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
                    presentation: WorkspaceModulePresentationProfile(
                        showsGridColumns: true, showsLocalSort: false, showsImportFolder: false,
                        showsFavorite: true, showsOnlineSave: true, showsWallhavenControls: false,
                        showsFavoritesFilter: false, filmstripAvailability: .resolvedImage,
                        refreshRequiresSelection: false, detailActions: .none
                    ),
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
                    presentation: WorkspaceModulePresentationProfile(
                        showsGridColumns: true, showsLocalSort: false, showsImportFolder: false,
                        showsFavorite: true, showsOnlineSave: false, showsWallhavenControls: true,
                        showsFavoritesFilter: false, filmstripAvailability: .none,
                        refreshRequiresSelection: false, detailActions: .none
                    ),
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
                ),
                WorkspaceModuleDescriptor(
                    id: .favorites,
                    displayName: "Favorites",
                    presentation: WorkspaceModulePresentationProfile(
                        showsGridColumns: true, showsLocalSort: false, showsImportFolder: false,
                        showsFavorite: true, showsOnlineSave: true, showsWallhavenControls: false,
                        showsFavoritesFilter: true, filmstripAvailability: .detail,
                        refreshRequiresSelection: false, detailActions: .none
                    ),
                    defaultRoute: {
                        WorkspaceRoute(moduleID: .favorites, itemID: FavoriteSourceFilter.all.rawValue)
                    },
                    makeContentController: { context in
                        FavoritesContentViewController(
                            moduleStore: favoritesModuleStore,
                            preferences: favoritesPreferences,
                            detailPane: context.detailPaneController
                        )
                    },
                    makeDetailController: { context in
                        FavoritesImageDetailViewController(
                            moduleStore: favoritesModuleStore,
                            detailStore: favoritesDetailStore,
                            immersive: context.immersive,
                            detailPane: context.detailPaneController,
                            detailInteraction: favoritesDetailInteraction,
                            filmstripVisibility: filmstripVisibility,
                            onOpenRecommendation: { source, recommendation in
                                switch source {
                                case .gallery:
                                    context.appContext.routeController.select(
                                        WorkspaceRoute(
                                            moduleID: .fourKHDGallery,
                                            itemID: GallerySection.latest.rawValue
                                        )
                                    )
                                    fourKHDGalleryStore.openRecommendation(recommendation)
                                case .missKon:
                                    context.appContext.routeController.select(
                                        WorkspaceRoute(
                                            moduleID: .missKon,
                                            itemID: MissKonSection.latest.rawValue
                                        )
                                    )
                                    missKonStore.openRecommendation(recommendation)
                                case .wallhaven:
                                    break
                                }
                            }
                        )
                    },
                    normalizeRoute: { route in
                        let filter = FavoriteSourceFilter(rawValue: route.itemID) ?? .all
                        return WorkspaceRoute(moduleID: .favorites, itemID: filter.rawValue)
                    },
                    applyRoute: { route in
                        guard let filter = FavoriteSourceFilter(rawValue: route.itemID) else { return }
                        if favoritesModuleStore.filter != filter {
                            favoritesModuleStore.filter = filter
                        }
                    },
                    bootstrap: {}
                )
            ]
        )
    }
}
