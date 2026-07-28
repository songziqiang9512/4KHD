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
}
