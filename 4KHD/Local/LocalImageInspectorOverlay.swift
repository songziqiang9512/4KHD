import AppKit
import SwiftUI

struct LocalImageInspectorOverlay: View {
    let image: LocalImageItem?
    let metadata: LocalImageMetadata?
    let onDismiss: () -> Void

    private let panelWidth: CGFloat = 356

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if image != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismiss()
                    }
                    .transition(.opacity)
            }

            if let image {
                LocalImageInspectorCard(image: image, metadata: metadata, onDismiss: dismiss)
                    .frame(width: panelWidth)
                    .padding(.top, 10)
                    .padding(.trailing, 18)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .onTapGesture {}
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(image != nil)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: image?.id)
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            onDismiss()
        }
    }
}

private struct LocalImageInspectorCard: View {
    let image: LocalImageItem
    let metadata: LocalImageMetadata?
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("详情")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 8)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.16))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.20), lineWidth: 0.5)
                        }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("关闭详情")
            }

            LocalImageInfoView(image: image, metadata: metadata)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(LocalInspectorGlassPanel(cornerRadius: 22, style: .regular))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.4), radius: 25, x: 0, y: 16)
    }
}

private struct LocalInspectorGlassPanel: NSViewRepresentable {
    let cornerRadius: CGFloat
    let style: NSGlassEffectView.Style

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        nsView.cornerRadius = cornerRadius
        nsView.style = style
        nsView.tintColor = LocalInspectorGlassPalette.baseTint(for: nsView)
        nsView.layer?.cornerRadius = cornerRadius
        nsView.layer?.cornerCurve = .continuous
        nsView.layer?.masksToBounds = true
        nsView.layer?.backgroundColor = LocalInspectorGlassPalette.innerFill(for: nsView).cgColor
    }
}

private enum LocalInspectorGlassPalette {
    static func baseTint(for view: NSView) -> NSColor {
        view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.12, alpha: 0.78)
            : NSColor(calibratedWhite: 0.98, alpha: 0.55)
    }

    static func innerFill(for view: NSView) -> NSColor {
        view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.08, alpha: 0.32)
            : NSColor(calibratedWhite: 1.0, alpha: 0.18)
    }
}
