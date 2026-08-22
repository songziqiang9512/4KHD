import AppKit

/// Returns the best window to host a modal sheet: the key window if visible,
/// otherwise the main window.
func appModalHostWindow() -> NSWindow? {
    if let keyWindow = NSApp.keyWindow, keyWindow.isVisible {
        return keyWindow
    }
    if let mainWindow = NSApp.mainWindow, mainWindow.isVisible {
        return mainWindow
    }
    return nil
}

/// Factory for creating styled alerts with centered text and a consistent
/// width.  Every alert in the app should go through this function so that
/// the visual style stays uniform.
func makeAppAlert(
    title: String,
    message: String = "",
    style: NSAlert.Style = .informational,
    buttons: [String] = ["好"],
    accessoryView: NSView? = nil
) -> NSAlert {
    let alert = NSAlert()
    alert.alertStyle = style
    alert.messageText = title
    alert.informativeText = message
    buttons.forEach { alert.addButton(withTitle: $0) }
    alert.accessoryView = accessoryView
    return alert
}

// MARK: - Styled presentation

/// Applies the app-wide dialog style and then presents the alert as a sheet
/// (when a window is available) or as a modal.
func presentAppAlert(
    _ alert: NSAlert,
    in window: NSWindow? = nil,
    completion: ((NSApplication.ModalResponse) -> Void)? = nil
) {
    alert.applyAppDialogStyle()

    if let window = window {
        alert.beginSheetModal(for: window, completionHandler: completion)
        return
    }

    let response = alert.runModal()
    completion?(response)
}

extension NSAlert {
    /// Keep dialogs on AppKit's public, native alert layout.
    func applyAppDialogStyle() {
        icon = NSApp.applicationIconImage
    }
}
