import AppKit
import SwiftUI

struct LocalImageGridKeyboardMonitor: NSViewRepresentable {
    let isActive: Bool
    let onKeyDown: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isActive: isActive, onKeyDown: onKeyDown)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isActive = isActive
        context.coordinator.onKeyDown = onKeyDown
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var isActive: Bool
        var onKeyDown: (NSEvent) -> Bool
        private var monitor: Any?

        init(isActive: Bool, onKeyDown: @escaping (NSEvent) -> Bool) {
            self.isActive = isActive
            self.onKeyDown = onKeyDown
        }

        deinit {
            uninstall()
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                guard shouldHandle(event) else { return event }
                return onKeyDown(event) ? nil : event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func shouldHandle(_ event: NSEvent) -> Bool {
            guard isActive,
                  event.hasBareKeyModifiers,
                  let window = event.window ?? NSApp.keyWindow,
                  window.isKeyWindow else { return false }
            if window.firstResponder is NSTextView {
                return false
            }
            return true
        }
    }
}
