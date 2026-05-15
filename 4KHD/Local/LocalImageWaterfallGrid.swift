import AppKit
import SwiftUI

struct LocalImageWaterfallGrid: View {
    let items: [(originalIndex: Int, image: LocalImageItem)]
    let metadataByImageID: [LocalImageItem.ID: LocalImageMetadata]
    let selectedImageID: LocalImageItem.ID?
    let scrollRequestID: Int
    let onRequestFocus: () -> Void
    let onSelect: (Int) -> Void
    let onQuickLook: (LocalImageItem) -> Void
    let onShowInfo: (LocalImageItem) -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = LocalWaterfallLayout.compute(
                items: items,
                metadataByImageID: metadataByImageID,
                availableWidth: proxy.size.width
            )

            ScrollViewReader { scrollProxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        ForEach(layout.items) { positioned in
                            let item = items[positioned.index]
                            LocalImageGridCard(
                                image: item.image,
                                fileExists: metadataByImageID[item.image.id]?.fileExists ?? true,
                                isSelected: selectedImageID == item.image.id
                            ) {
                                onSelect(item.originalIndex)
                            } onQuickLook: {
                                onQuickLook(item.image)
                            } onShowInfo: {
                                onShowInfo(item.image)
                            }
                            .frame(width: positioned.frame.width, height: positioned.frame.height)
                            .position(x: positioned.frame.midX, y: positioned.frame.midY)
                            .id(item.image.id)
                        }
                    }
                    .frame(width: proxy.size.width, height: layout.contentHeight, alignment: .topLeading)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        onRequestFocus()
                    }
                )
                .onChange(of: scrollRequestID) { _, _ in
                    guard let selectedImageID else { return }
                    withAnimation(.easeInOut(duration: 0.18)) {
                        scrollProxy.scrollTo(selectedImageID)
                    }
                }
            }
        }
    }
}

private struct LocalImageGridCard: View {
    let image: LocalImageItem
    let fileExists: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onQuickLook: () -> Void
    let onShowInfo: () -> Void

    @State private var isHovering = false
    @State private var isPressing = false

    var body: some View {
        Button(action: onSelect) {
            RemoteImageView(url: image.url, contentMode: .fill, priority: .utility, localMaxPixelSize: 420) {
                Rectangle()
                    .fill(.quaternary)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                if !fileExists {
                    ZStack {
                        Color.black.opacity(0.42)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.86))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .overlay(selectionOverlay)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .scaleEffect(cardScale)
        .animation(.timingCurve(0.22, 0.86, 0.26, 1.0, duration: isHovering ? 0.30 : 0.34), value: isHovering)
        .animation(.timingCurve(0.22, 0.86, 0.26, 1.0, duration: isPressing ? 0.08 : 0.12), value: isPressing)
        .onHover { hovering in
            isHovering = hovering
            if !hovering { isPressing = false }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressing = true }
                .onEnded { _ in isPressing = false }
        )
        .contextMenu {
            Button("设置为桌面壁纸") {
                LocalDesktopWallpaperSetter.setDesktopWallpaper(image.url)
            }
            Divider()
            Button("快速预览") {
                onQuickLook()
            }
            Button("详细信息") {
                onShowInfo()
            }
            Button("在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([image.url])
            }
            Button("复制路径") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(image.url.path, forType: .string)
            }
            Button("打开文件") {
                NSWorkspace.shared.open(image.url)
            }
        }
        .zIndex(isHovering || isSelected ? 1 : 0)
    }

    private var cardScale: CGFloat {
        if isPressing { return 0.96 }
        return isHovering ? 1.05 : 1
    }

    @ViewBuilder
    private var selectionOverlay: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(
                isSelected ? Color.accentColor : hoverStrokeColor,
                lineWidth: isSelected ? 2 : 1
            )
    }

    private var hoverStrokeColor: Color {
        isHovering ? .primary.opacity(0.65) : .primary.opacity(0.16)
    }
}

private struct LocalWaterfallPosition: Identifiable {
    let id: LocalImageItem.ID
    let index: Int
    let frame: CGRect
}

private struct LocalWaterfallLayoutResult {
    let items: [LocalWaterfallPosition]
    let contentHeight: CGFloat
}

private enum LocalWaterfallLayout {
    static func compute(
        items: [(originalIndex: Int, image: LocalImageItem)],
        metadataByImageID: [LocalImageItem.ID: LocalImageMetadata],
        availableWidth: CGFloat
    ) -> LocalWaterfallLayoutResult {
        let inset: CGFloat = 12
        let baseSpacing: CGFloat = 10
        let horizontalSpacing: CGFloat = 8
        let contentWidth = max(0, availableWidth - inset * 2)
        let columns = columnCount(for: contentWidth)
        let estimatedColumnWidth = max(60, (contentWidth - horizontalSpacing * CGFloat(columns - 1)) / CGFloat(columns))
        let hoverScale: CGFloat = 1.05
        let hoverSpacing = estimatedColumnWidth * (hoverScale - 1)
        let columnSpacing = max(horizontalSpacing, hoverSpacing)
        let rowSpacing = max(baseSpacing, hoverSpacing)
        let columnWidth = max(60, (contentWidth - columnSpacing * CGFloat(columns - 1)) / CGFloat(columns))
        var columnHeights = [CGFloat](repeating: inset, count: columns)
        var positions: [LocalWaterfallPosition] = []

        for index in items.indices {
            let image = items[index].image
            let column = columnHeights.indices.min { columnHeights[$0] < columnHeights[$1] } ?? 0
            let x = inset + CGFloat(column) * (columnWidth + columnSpacing)
            let y = columnHeights[column]
            let ratio = aspectRatio(for: metadataByImageID[image.id])
            let height = columnWidth / ratio
            let frame = CGRect(x: x, y: y, width: columnWidth, height: height)
            positions.append(LocalWaterfallPosition(id: image.id, index: index, frame: frame))
            columnHeights[column] += height + rowSpacing
        }

        let contentHeight = max((columnHeights.max() ?? inset) + inset - rowSpacing, inset * 2)
        return LocalWaterfallLayoutResult(items: positions, contentHeight: contentHeight)
    }

    private static func columnCount(for width: CGFloat) -> Int {
        if width >= 1_200 { return 6 }
        if width >= 900 { return 5 }
        if width >= 600 { return 4 }
        if width >= 360 { return 3 }
        if width >= 180 { return 2 }
        return 1
    }

    private static func aspectRatio(for metadata: LocalImageMetadata?) -> CGFloat {
        guard let width = metadata?.pixelWidth,
              let height = metadata?.pixelHeight,
              width > 0,
              height > 0 else {
            return 16.0 / 9.0
        }

        let ratio = CGFloat(width) / CGFloat(height)
        return max(0.25, min(3.0, ratio))
    }
}
