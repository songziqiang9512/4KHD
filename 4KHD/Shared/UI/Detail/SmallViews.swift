import AppKit
import SwiftUI

struct LocalImageThumbnail: View {
    let url: URL

    var body: some View {
        RemoteImageView(url: url, contentMode: .fill, priority: .utility, localMaxPixelSize: 220) {
            Rectangle()
                .fill(.quaternary)
                .overlay(Image(systemName: "photo").font(.caption).foregroundStyle(.secondary))
        }
        .frame(width: 72, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct StepButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().stroke(.separator, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

struct LoadingFilmstripTile: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
            Text("加载中")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 72, height: 96)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct DetailPlaceholder: View {
    enum Kind {
        case loading
        case failed
    }

    let kind: Kind
    var onRetry: (() -> Void)? = nil
    var onOpenOriginal: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            switch kind {
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .frame(width: 32, height: 32)
                Text("加载中")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            case .failed:
                Image(systemName: "photo")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("详情解析失败")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    if let onRetry {
                        Button("重试", action: onRetry)
                    }
                    if let onOpenOriginal {
                        Button("打开原网页", action: onOpenOriginal)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

struct DetailStatusBadge: View {
    enum Kind {
        case resolving
        case prefetching
        case saving
        case saved
        case failed
    }

    let kind: Kind
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            switch kind {
            case .resolving, .prefetching, .saving:
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.hierarchical)
            }

            Text(text)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }
}

struct KeyDownCatcher: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = KeyCatcherView()
        view.onKeyDown = onKeyDown
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? KeyCatcherView else { return }
        view.onKeyDown = onKeyDown
        DispatchQueue.main.async {
            if view.window?.firstResponder == nil {
                view.window?.makeFirstResponder(view)
            }
        }
    }

    private final class KeyCatcherView: NSView {
        var onKeyDown: (NSEvent) -> Bool = { _ in false }

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if !onKeyDown(event) {
                super.keyDown(with: event)
            }
        }
    }
}

enum DetailKeyCommand {
    case previous
    case next
    case quickLook
    case toggleImmersive

    init?(event: NSEvent) {
        guard event.hasBareKeyModifiers else { return nil }
        switch event.keyCode {
        case 123:
            self = .previous
        case 124:
            self = .next
        case 49:
            self = .quickLook
        case 3:
            self = .toggleImmersive
        default:
            return nil
        }
    }
}

extension NSEvent {
    var hasBareKeyModifiers: Bool {
        modifierFlags
            .intersection([.command, .option, .control, .shift])
            .isEmpty
    }
}
