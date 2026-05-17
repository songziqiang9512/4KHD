import AppKit

extension NSEvent {
    var hasBareKeyModifiers: Bool {
        modifierFlags
            .intersection([.command, .option, .control, .shift])
            .isEmpty
    }
}
