import SwiftUI

enum WorkspaceAppAssembly {
    @MainActor
    static func makeAppContext() -> WorkspaceAppContext {
        let fourKHDGalleryStore = FourKHDGalleryStore()
        let galleryPreferences = GalleryContentPreferences()
        let galleryDetailInteraction = GalleryDetailInteractionController()
        let localLibraryStore = LocalLibraryStore()
        let localPreferences = LocalLibraryContentPreferences()
        let localDetailInteraction = LocalDetailInteractionController()
        let localInspector = LocalImageInspectorController()
        let filmstripVisibility = FilmstripVisibilityController()
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
            localInspector: localInspector,
            filmstripVisibility: filmstripVisibility
        )
        let toolbarContext = WorkspaceToolbarContext(
            galleryStore: fourKHDGalleryStore,
            galleryPreferences: galleryPreferences,
            galleryDetailInteraction: galleryDetailInteraction,
            localLibraryStore: localLibraryStore,
            localPreferences: localPreferences,
            localDetailInteraction: localDetailInteraction,
            localInspector: localInspector,
            filmstripVisibility: filmstripVisibility,
            importRootFolderAction: importRootFolderAction
        )

        return WorkspaceAppContext(
            moduleRegistry: moduleRegistry,
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
        localInspector: LocalImageInspectorController,
        filmstripVisibility: FilmstripVisibilityController
    ) -> WorkspaceModuleRegistry {
        return WorkspaceModuleRegistry(
            modules: [
                WorkspaceModuleDescriptor(
                    id: .fourKHDGallery,
                    displayName: "4KHDGallery",
                    defaultRoute: {
                        WorkspaceRoute(moduleID: .fourKHDGallery, itemID: GallerySection.latest.rawValue)
                    },
                    makeSidebarSection: { selection, _ in
                        AnyView(
                            FourKHDGallerySidebarSection(selection: selection)
                                .environment(fourKHDGalleryStore)
                        )
                    },
                    makeContentView: {
                        AnyView(
                            GalleryContentList()
                                .environment(fourKHDGalleryStore)
                                .environment(galleryPreferences)
                        )
                    },
                    makeDetailView: {
                        AnyView(
                            ImageDetailPane()
                                .environment(fourKHDGalleryStore)
                                .environment(galleryDetailInteraction)
                                .environment(filmstripVisibility)
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
                ),
                WorkspaceModuleDescriptor(
                    id: .localLibrary,
                    displayName: "LocalLibrary",
                    defaultRoute: {
                        if let folderID = localLibraryStore.defaultFolderID {
                            return WorkspaceRoute(moduleID: .localLibrary, itemID: folderID)
                        }
                        return WorkspaceRoute(moduleID: .localLibrary, itemID: "")
                    },
                    makeSidebarSection: { selection, importRootFolder in
                        AnyView(
                            LocalLibrarySidebarSection(selection: selection, importRootFolder: importRootFolder)
                                .environment(localLibraryStore)
                        )
                    },
                    makeContentView: {
                        AnyView(
                            LocalImageContentList()
                                .environment(localLibraryStore)
                                .environment(localPreferences)
                                .environment(localInspector)
                        )
                    },
                    makeDetailView: {
                        AnyView(
                            LocalImageDetailPane()
                                .environment(localLibraryStore)
                                .environment(localDetailInteraction)
                                .environment(localInspector)
                                .environment(filmstripVisibility)
                        )
                    },
                    normalizeRoute: { route in
                        if let folder = localLibraryStore.findFolder(id: route.itemID) {
                            return WorkspaceRoute(moduleID: .localLibrary, itemID: folder.id)
                        }
                        if let folderID = localLibraryStore.defaultFolderID {
                            return WorkspaceRoute(moduleID: .localLibrary, itemID: folderID)
                        }
                        return WorkspaceRoute(moduleID: .localLibrary, itemID: "")
                    },
                    applyRoute: { route in
                        if let folder = localLibraryStore.findFolder(id: route.itemID) {
                            localLibraryStore.selectFolder(folder)
                        }
                    },
                    bootstrap: {}
                )
            ]
        )
    }
}
