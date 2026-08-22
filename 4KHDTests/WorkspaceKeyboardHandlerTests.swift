import AppKit
import XCTest
@testable import _KHD

final class WorkspaceKeyboardHandlerTests: XCTestCase {
    @MainActor
    func testCommandZeroRoutesToFitWindow() throws {
        var resetCount = 0
        var sidebarCount = 0
        let context = WorkspaceKeyboardContext(
            toggleSidebar: { sidebarCount += 1 },
            resetZoom: { resetCount += 1 }
        )

        let handled = WorkspaceKeyboardHandler.keyDown(
            try keyEvent(characters: "0", modifiers: [.command], keyCode: 29),
            context: context
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(resetCount, 1)
        XCTAssertEqual(sidebarCount, 0)
    }

    @MainActor
    func testExtraModifierDoesNotTriggerCommandRoute() throws {
        var resetCount = 0
        let context = WorkspaceKeyboardContext(resetZoom: { resetCount += 1 })

        let handled = WorkspaceKeyboardHandler.keyDown(
            try keyEvent(characters: "0", modifiers: [.command, .option], keyCode: 29),
            context: context
        )

        XCTAssertFalse(handled)
        XCTAssertEqual(resetCount, 0)
    }

    @MainActor
    func testCommandFocusAndDetailShortcutsUseExactCommandModifier() throws {
        var calls: [String] = []
        let context = WorkspaceKeyboardContext(
            toggleDetailPane: { calls.append("detail") },
            focusSidebar: { calls.append("sidebar"); return true },
            focusContent: { calls.append("content"); return true },
            focusDetail: { calls.append("detail-focus"); return true }
        )

        XCTAssertTrue(WorkspaceKeyboardHandler.keyDown(
            try keyEvent(characters: "\\", modifiers: [.command], keyCode: 42),
            context: context
        ))
        XCTAssertTrue(WorkspaceKeyboardHandler.keyDown(
            try keyEvent(characters: "1", modifiers: [.command], keyCode: 18),
            context: context
        ))
        XCTAssertTrue(WorkspaceKeyboardHandler.keyDown(
            try keyEvent(characters: "2", modifiers: [.command], keyCode: 19),
            context: context
        ))
        XCTAssertTrue(WorkspaceKeyboardHandler.keyDown(
            try keyEvent(characters: "3", modifiers: [.command], keyCode: 20),
            context: context
        ))

        XCTAssertEqual(calls, ["detail", "sidebar", "content", "detail-focus"])
    }

    private func keyEvent(
        characters: String,
        modifiers: NSEvent.ModifierFlags,
        keyCode: UInt16
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}
