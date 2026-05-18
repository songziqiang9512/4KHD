import AppKit

@MainActor
struct WorkspaceKeyboardContext {
    var toggleSidebar: (() -> Void)?
    var toggleDetailPane: (() -> Void)?
    var focusSidebar: (() -> Bool)?
    var focusContent: (() -> Bool)?
    var focusDetail: (() -> Bool)?
    var stepSelection: ((Int) -> Bool)?
    var quickLook: (() -> Bool)?
    var toggleImmersive: (() -> Bool)?
}

@MainActor
enum WorkspaceKeyboardHandler {
    static func keyDown(_ event: NSEvent, context: WorkspaceKeyboardContext) -> Bool {
        if event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            switch event.keyCode {
            case 3:
                return context.toggleImmersive?() ?? false
            case 49:
                return context.quickLook?() ?? false
            case 123, 126:
                return context.stepSelection?(-1) ?? false
            case 124, 125:
                return context.stepSelection?(1) ?? false
            default:
                break
            }
        }

        if event.modifierFlags.intersection([.command]) == [.command] {
            switch event.charactersIgnoringModifiers {
            case "0":
                context.toggleSidebar?()
                return true
            case "\\":
                context.toggleDetailPane?()
                return true
            case "1":
                return context.focusSidebar?() ?? false
            case "2":
                return context.focusContent?() ?? false
            case "3":
                return context.focusDetail?() ?? false
            default:
                break
            }
        }

        return false
    }
}
