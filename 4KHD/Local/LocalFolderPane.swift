import AppKit
import ImageIO
import SwiftUI

private enum LocalContentLayout: String {
    case list
    case grid
}

private enum LocalImageSortField: String, CaseIterable, Identifiable {
    case name
    case modifiedDate
    case fileSize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "文件名"
        case .modifiedDate: "修改时间"
        case .fileSize: "文件大小"
        }
    }
}

private enum LocalImageSortDirection: String, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ascending: "正序"
        case .descending: "逆序"
        }
    }
}

private struct LocalImageMetadata: Sendable {
    let fileSize: Int64?
    let modifiedDate: Date?
    let pixelWidth: Int?
    let pixelHeight: Int?
}

/// 三段式中部内容栏 —— 显示当前所选本地目录里的所有图片，
/// selection 由 `LocalLibraryStore.selectedImageIndex` 桥接。
struct LocalImageContentList: View {
    @Environment(LocalLibraryStore.self) private var localLibrary
    @AppStorage("com.songziqiang.4khd.localContentLayout.v1") private var contentLayoutRaw = LocalContentLayout.grid.rawValue
    @AppStorage("com.songziqiang.4khd.localImageSortField.v1") private var imageSortFieldRaw = LocalImageSortField.name.rawValue
    @AppStorage("com.songziqiang.4khd.localImageSortDirection.v1") private var imageSortDirectionRaw = LocalImageSortDirection.ascending.rawValue
    @State private var searchText = ""
    @State private var metadataByImageID: [LocalImageItem.ID: LocalImageMetadata] = [:]

    private var selectionBinding: Binding<LocalImageItem.ID?> {
        Binding(
            get: { localLibrary.selectedImage?.id },
            set: { newValue in
                guard let newValue,
                      let index = localLibrary.selectedImages.firstIndex(where: { $0.id == newValue }) else { return }
                // 避免在 view update 周期内直接写 @Published
                DispatchQueue.main.async {
                    localLibrary.selectImage(at: index)
                }
            }
        )
    }

    var body: some View {
        Group {
            if localLibrary.roots.isEmpty {
                ContentUnavailableView {
                    Label("还没有本地目录", systemImage: "folder")
                } description: {
                    Text("使用侧栏右上的 + 导入一个图片目录")
                } actions: {
                    Button("选择目录…") { importRootFolder() }
                        .controlSize(.large)
                }
            } else if let folder = localLibrary.selectedFolder {
                if folder.images.isEmpty {
                    ContentUnavailableView("当前目录没有图片", systemImage: "photo.on.rectangle.angled")
                        .navigationTitle(folder.title)
                } else if filteredImages.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .navigationTitle(folder.title)
                        .navigationSubtitle("0 / \(folder.images.count) 张")
                } else {
                    content(for: folder)
                        .navigationTitle(folder.title)
                        .navigationSubtitle(navigationSubtitle(for: folder))
                }
            } else {
                ContentUnavailableView("从侧栏选择目录", systemImage: "sidebar.left")
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索本地图片")
        .task(id: localLibrary.selectedFolder?.id) {
            await loadMetadata(for: localLibrary.selectedImages)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("显示方式", selection: $contentLayoutRaw) {
                    Label("列表", systemImage: "list.bullet").tag(LocalContentLayout.list.rawValue)
                    Label("网格", systemImage: "square.grid.2x2").tag(LocalContentLayout.grid.rawValue)
                }
                .pickerStyle(.segmented)
                .frame(width: 92)
                .help("切换列表 / 网格")
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Text("排序方式")
                    ForEach(LocalImageSortField.allCases) { field in
                        Button {
                            imageSortFieldRaw = field.rawValue
                        } label: {
                            if imageSortField == field {
                                Label(field.title, systemImage: "checkmark")
                            } else {
                                Text(field.title)
                            }
                        }
                    }

                    Divider()
                    Text("顺序")
                    ForEach(LocalImageSortDirection.allCases) { direction in
                        Button {
                            imageSortDirectionRaw = direction.rawValue
                        } label: {
                            if imageSortDirection == direction {
                                Label(direction.title, systemImage: "checkmark")
                            } else {
                                Text(direction.title)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .help("排序")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    localLibrary.refreshSelectedRoot()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新本地目录")
                .disabled(localLibrary.selectedFolder == nil || localLibrary.isScanning)
            }
        }
    }

    @ViewBuilder
    private func content(for folder: LocalFolderNode) -> some View {
        switch contentLayout {
        case .list:
            List(selection: selectionBinding) {
                ForEach(filteredImagesWithOriginalIndex, id: \.image.id) { item in
                    LocalImageRow(
                        image: item.image,
                        metadata: metadataByImageID[item.image.id]
                    )
                        .tag(item.image.id)
                        .contextMenu { imageContextMenu(for: item.image) }
                }
            }
            .listStyle(.inset)
        case .grid:
            LocalImageWaterfallGrid(
                items: filteredImagesWithOriginalIndex,
                metadataByImageID: metadataByImageID,
                selectedImageID: localLibrary.selectedImage?.id
            ) { index in
                localLibrary.selectImage(at: index)
            }
            .background(.background)
        }
    }

    private var contentLayout: LocalContentLayout {
        LocalContentLayout(rawValue: contentLayoutRaw) ?? .grid
    }

    private var imageSortField: LocalImageSortField {
        LocalImageSortField(rawValue: imageSortFieldRaw) ?? .name
    }

    private var imageSortDirection: LocalImageSortDirection {
        LocalImageSortDirection(rawValue: imageSortDirectionRaw) ?? .ascending
    }

    private var filteredImages: [LocalImageItem] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return localLibrary.selectedImages
        }
        return filteredImagesWithOriginalIndex.map(\.image)
    }

    private var filteredImagesWithOriginalIndex: [(originalIndex: Int, image: LocalImageItem)] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = Array(localLibrary.selectedImages.enumerated()).map { ($0.offset, $0.element) }
        let filtered: [(originalIndex: Int, image: LocalImageItem)]
        if query.isEmpty {
            filtered = items
        } else {
            filtered = items.compactMap { index, image in
                image.title.localizedStandardContains(query) ? (index, image) : nil
            }
        }

        return filtered.sorted { lhs, rhs in
            compare(lhs.image, rhs.image) == .orderedAscending
        }
    }

    private func navigationSubtitle(for folder: LocalFolderNode) -> String {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(folder.images.count) 张"
        }
        return "\(filteredImages.count) / \(folder.images.count) 张"
    }

    private func compare(_ lhs: LocalImageItem, _ rhs: LocalImageItem) -> ComparisonResult {
        let result: ComparisonResult
        switch imageSortField {
        case .name:
            result = lhs.title.localizedStandardCompare(rhs.title)
        case .modifiedDate:
            let lhsDate = metadataByImageID[lhs.id]?.modifiedDate ?? .distantFuture
            let rhsDate = metadataByImageID[rhs.id]?.modifiedDate ?? .distantFuture
            if lhsDate != rhsDate {
                result = lhsDate < rhsDate ? .orderedAscending : .orderedDescending
            } else {
                result = lhs.title.localizedStandardCompare(rhs.title)
            }
        case .fileSize:
            let lhsSize = metadataByImageID[lhs.id]?.fileSize ?? 0
            let rhsSize = metadataByImageID[rhs.id]?.fileSize ?? 0
            if lhsSize != rhsSize {
                result = lhsSize < rhsSize ? .orderedAscending : .orderedDescending
            } else {
                result = lhs.title.localizedStandardCompare(rhs.title)
            }
        }

        switch imageSortDirection {
        case .ascending:
            return result
        case .descending:
            switch result {
            case .orderedAscending: return .orderedDescending
            case .orderedDescending: return .orderedAscending
            case .orderedSame: return .orderedSame
            }
        }
    }

    @ViewBuilder
    private func imageContextMenu(for image: LocalImageItem) -> some View {
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

    private func loadMetadata(for images: [LocalImageItem]) async {
        let metadata = await Task.detached(priority: .utility) {
            var result: [LocalImageItem.ID: LocalImageMetadata] = [:]
            let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
            for image in images {
                guard !Task.isCancelled else { return result }
                let values = try? image.url.resourceValues(forKeys: keys)
                let pixelSize = pixelSize(for: image.url)
                result[image.id] = LocalImageMetadata(
                    fileSize: values?.fileSize.map(Int64.init),
                    modifiedDate: values?.contentModificationDate,
                    pixelWidth: pixelSize?.width,
                    pixelHeight: pixelSize?.height
                )
            }
            return result
        }.value

        guard !Task.isCancelled else { return }
        metadataByImageID = metadata
    }

    private func importRootFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "导入"
        panel.message = "选择一个包含图片的文件夹"
        guard panel.runModal() == .OK, let folderURL = panel.url else { return }
        localLibrary.importRootFolder(folderURL)
    }
}

private struct LocalImageRow: View {
    let image: LocalImageItem
    let metadata: LocalImageMetadata?

    var body: some View {
        HStack(spacing: 10) {
            RemoteImageView(url: image.url, contentMode: .fill, priority: .utility, localMaxPixelSize: 160) {
                Rectangle().fill(.quaternary)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
            .frame(width: 56, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 3) {
                Text(image.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let resolutionText {
                    Text(resolutionText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if let secondaryMetadataText {
                    Text(secondaryMetadataText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var resolutionText: String? {
        formattedResolution(metadata)
    }

    private var secondaryMetadataText: String? {
        formattedSecondaryMetadata(metadata)
    }
}

private struct LocalImageGridCard: View {
    let image: LocalImageItem
    let isSelected: Bool
    let onSelect: () -> Void

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
        .contextMenu { localImageContextMenu(for: image) }
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

private struct LocalImageWaterfallGrid: View {
    let items: [(originalIndex: Int, image: LocalImageItem)]
    let metadataByImageID: [LocalImageItem.ID: LocalImageMetadata]
    let selectedImageID: LocalImageItem.ID?
    let onSelect: (Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = LocalWaterfallLayout.compute(
                items: items,
                metadataByImageID: metadataByImageID,
                availableWidth: proxy.size.width
            )

            ScrollView {
                ZStack(alignment: .topLeading) {
                    ForEach(layout.items) { positioned in
                        let item = items[positioned.index]
                        LocalImageGridCard(
                            image: item.image,
                            isSelected: selectedImageID == item.image.id
                        ) {
                            onSelect(item.originalIndex)
                        }
                        .frame(width: positioned.frame.width, height: positioned.frame.height)
                        .position(x: positioned.frame.midX, y: positioned.frame.midY)
                    }
                }
                .frame(width: proxy.size.width, height: layout.contentHeight, alignment: .topLeading)
            }
        }
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

@ViewBuilder
private func localImageContextMenu(for image: LocalImageItem) -> some View {
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

private func formattedResolution(_ metadata: LocalImageMetadata?) -> String? {
    guard let metadata else { return nil }
    guard let pixelWidth = metadata.pixelWidth, let pixelHeight = metadata.pixelHeight else {
        return nil
    }
    return "\(pixelWidth)×\(pixelHeight)"
}

private func formattedSecondaryMetadata(_ metadata: LocalImageMetadata?) -> String? {
    guard let metadata else { return nil }
    var parts: [String] = []
    if let fileSize = metadata.fileSize {
        parts.append(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
    }
    if let modifiedDate = metadata.modifiedDate {
        parts.append(modifiedDate.formatted(date: .numeric, time: .omitted))
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

nonisolated private func pixelSize(for url: URL) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
        return nil
    }

    let width = properties[kCGImagePropertyPixelWidth] as? Int
    let height = properties[kCGImagePropertyPixelHeight] as? Int
    guard let width, let height else { return nil }
    return (width, height)
}
