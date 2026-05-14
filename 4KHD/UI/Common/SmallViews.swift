import AppKit
import SwiftUI

/// 列表 / 详情通用的小组件集合：图集封面占位、内容类型徽标、步进按钮、缩略图占位等。
/// 单独放在一起避免散成一堆 10 行的小文件。

struct PosterWebImage: View {
    let url: URL?
    let contentMode: ContentMode

    var body: some View {
        RemoteImageView(url: url, contentMode: contentMode, priority: .background, remoteMaxPixelSize: 180) {
            Rectangle()
                .fill(.quaternary)
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }
}

struct SlotThumbnail: View {
    let slot: ImageSlot

    var body: some View {
        RemoteImageView(url: slot.knownURL, contentMode: .fill, priority: .low, remoteMaxPixelSize: 220) {
            Rectangle()
                .fill(.quaternary)
                .overlay(Image(systemName: "photo").font(.caption).foregroundStyle(.secondary))
        }
        .frame(width: 72, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct KindBadge: View {
    let kind: ContentKind

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .foregroundStyle(color)
    }

    private var title: String {
        switch kind {
        case .gallery: "图集"
        case .recommended: "推荐"
        case .advertisement: "广告"
        }
    }

    private var color: Color {
        switch kind {
        case .gallery: .secondary
        case .recommended: .blue
        case .advertisement: .orange
        }
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

    var body: some View {
        VStack(spacing: 12) {
            switch kind {
            case .loading:
                ProgressView()
                    .controlSize(.large)
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
            }
        }
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
    case toggleImmersive

    init?(event: NSEvent) {
        guard event.hasBareKeyModifiers else { return nil }
        switch event.keyCode {
        case 123:
            self = .previous
        case 124, 49:
            self = .next
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
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.capsLock)
            .isEmpty
    }
}
