import XCTest
@testable import _KHD

final class WorkspaceRouteTests: XCTestCase {
    @MainActor
    func testRoundTripPreservesUnicodeAndSeparators() {
        let route = WorkspaceRoute(moduleID: .missKon, itemID: "人物|风景/中文")

        XCTAssertEqual(WorkspaceRoute(rawValue: route.rawValue), route)
    }

    @MainActor
    func testRejectsUnknownModuleAndMalformedPayload() {
        XCTAssertNil(WorkspaceRoute(rawValue: "unknown|aXRlbQ=="))
        XCTAssertNil(WorkspaceRoute(rawValue: "wallhaven|%%%"))
    }
}
