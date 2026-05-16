import AppKit
import SwiftUI

struct LocalImageInfoView: View {
    let image: LocalImageItem
    let metadata: LocalImageMetadata?

    private let previewHeight: CGFloat = 156
    private let topScrollFadeHeight: CGFloat = 12
    private let bottomScrollFadeHeight: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    previewSection
                    contentSection
                    noticeSection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 2)
                .padding(.top, 10)
            }
            .mask {
                LocalInspectorScrollFadeMask(
                    topFadeHeight: topScrollFadeHeight,
                    bottomFadeHeight: bottomScrollFadeHeight
                )
            }

            footerActions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImageView(url: image.url, contentMode: .fill, priority: .utility, localMaxPixelSize: 420) {
                Rectangle()
                    .fill(.quaternary)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
            .frame(maxWidth: .infinity)
            .frame(height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 0.45)
            }

            Text(image.title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let secondaryText {
                Text(secondaryText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !facts.isEmpty {
                Divider()
                    .overlay(Color.white.opacity(0.035))

                VStack(alignment: .leading, spacing: 6) {
                    Text("原数据")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                        ForEach(facts, id: \.label) { fact in
                            inspectorFact(label: fact.label, value: fact.value)
                        }
                    }
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.035))

            VStack(alignment: .leading, spacing: 5) {
                Text("文件位置")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(image.url.path)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var noticeSection: some View {
        if metadata?.fileExists == false {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                    .overlay(Color.white.opacity(0.035))
                
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("原始图片文件当前不可用")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footerActions: some View {
        HStack(spacing: 6) {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([image.url])
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("查看文件")
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(LocalInspectorFooterButtonStyle())

            Button {
                LocalQuickLookController.shared.open(url: image.url)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                        .font(.system(size: 14, weight: .semibold))
                    Text("快速预览")
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(LocalInspectorFooterButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private func inspectorFact(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var secondaryText: String? {
        [formattedSecondaryMetadata(metadata), image.url.pathExtension.uppercased().nilIfEmpty]
            .compactMap { $0 }
            .joined(separator: "  ·  ")
            .nilIfEmpty
    }

    private var facts: [(label: String, value: String)] {
        [
            formattedResolution(metadata).map { ("分辨率", $0) },
            metadata?.fileSize.map { ("文件大小", ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)) },
            metadata?.modifiedDate.map { ("修改时间", $0.formatted(date: .numeric, time: .shortened)) },
            image.url.pathExtension.isEmpty ? nil : ("格式", image.url.pathExtension.uppercased())
        ]
        .compactMap { $0 }
    }
}

private struct LocalInspectorFooterButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(nsColor: .labelColor))
            .background(Color.black.opacity(configuration.isPressed ? 0.126 : 0.14))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(isEnabled ? 0.16 : 0.09), lineWidth: 0.7)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct LocalInspectorScrollFadeMask: View {
    let topFadeHeight: CGFloat
    let bottomFadeHeight: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, topFadeHeight + bottomFadeHeight + 1)
            let topFadeRatio = min(max(topFadeHeight / height, 0.01), 0.18)
            let bottomFadeRatio = min(max(bottomFadeHeight / height, 0.01), 0.24)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: topFadeRatio),
                    .init(color: .black, location: 1 - bottomFadeRatio),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
