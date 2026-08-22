import AppKit
import XCTest
@testable import _KHD

final class WorkspaceModuleRegistryTests: XCTestCase {
    @MainActor
    func testModuleBootstrapsOnlyOnce() {
        var bootstrapCount = 0
        let descriptor = WorkspaceModuleDescriptor(
            id: .localLibrary,
            displayName: "Local",
            defaultRoute: { WorkspaceRoute(moduleID: .localLibrary, itemID: "all") },
            makeContentController: { _ in NSViewController() },
            makeDetailController: { _ in NSViewController() },
            normalizeRoute: { $0 },
            applyRoute: { _ in },
            bootstrap: { bootstrapCount += 1 }
        )
        let registry = WorkspaceModuleRegistry(modules: [descriptor])

        registry.bootstrapModule(.localLibrary)
        registry.bootstrapModule(.localLibrary)

        XCTAssertEqual(bootstrapCount, 1)
    }

    @MainActor
    func testModulePresentationCapabilitiesTravelWithDescriptor() {
        let profile = WorkspaceModulePresentationProfile(
            showsGridColumns: true,
            showsLocalSort: false,
            showsImportFolder: false,
            showsFavorite: true,
            showsOnlineSave: true,
            showsWallhavenControls: false,
            showsFavoritesFilter: false,
            filmstripAvailability: .detail,
            refreshRequiresSelection: false,
            detailActions: .none
        )
        let descriptor = WorkspaceModuleDescriptor(
            id: .fourKHDGallery,
            displayName: "Gallery",
            presentation: profile,
            defaultRoute: { WorkspaceRoute(moduleID: .fourKHDGallery, itemID: "latest") },
            makeContentController: { _ in NSViewController() },
            makeDetailController: { _ in NSViewController() },
            normalizeRoute: { $0 },
            applyRoute: { _ in },
            bootstrap: {}
        )
        let registry = WorkspaceModuleRegistry(modules: [descriptor])

        XCTAssertEqual(registry.descriptor(for: .fourKHDGallery)?.presentation, profile)
    }
}
