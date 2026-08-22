import AppKit
import XCTest
@testable import _KHD

final class WorkspaceChromeTests: XCTestCase {
    @MainActor
    func testColumnHostDoesNotWrapScrollableContentInVisualEffectMaterial() {
        let host = WorkspaceColumnHostController()
        let content = NSViewController()

        host.setContentController(content)

        XCTAssertFalse(host.view is NSVisualEffectView)
        XCTAssertIdentical(content.view.superview, host.view)
    }
}
