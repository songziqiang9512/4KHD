import AppKit
import SwiftUI

/// 三段式中部内容栏 —— 显示当前所选本地目录里的所有图片，
/// selection 由 `LocalLibraryStore.selectedImageIndex` 桥接。
struct LocalImageContentList: View {
    @Environment(LocalLibraryStore.self) private var localLibrary
    @Environment(LocalLibraryContentPreferences.self) private var preferences
    @Environment(WorkspaceDetailPaneController.self) private var detailPane
    @State private var metadataByImageID: [LocalImageItem.ID: LocalImageMetadata] = [:]
    @State private var infoImage: LocalImageItem?

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
                    Button("选择目录…") { chooseAndImportRootFolder() }
                        .controlSize(.large)
                }
            } else if let folder = localLibrary.selectedFolder {
                if folder.images.isEmpty {
                    ContentUnavailableView("当前目录没有图片", systemImage: "photo.on.rectangle.angled")
                        .navigationTitle(folder.title)
                } else if filteredImages.isEmpty {
                    ContentUnavailableView.search(text: preferences.searchText)
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
        .task(id: localLibrary.selectedFolder?.id) {
            await loadMetadata(for: localLibrary.selectedImages)
        }
        .task(id: localLibrary.selectedFolder?.id) {
            await monitorFileAvailability()
        }
        .overlay(alignment: .topTrailing) {
            LocalImageInspectorOverlay(
                image: infoImage,
                metadata: inspectedMetadata,
                onDismiss: { infoImage = nil }
            )
        }
        .onChange(of: localLibrary.selectedImage?.id) { _, _ in
            guard infoImage != nil else { return }
            infoImage = localLibrary.selectedImage
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
                selectedImageID: localLibrary.selectedImage?.id,
                preferredColumnCount: detailPane.gridColumnLimit,
                preferredCardMinimumWidth: detailPane.preferredGridCardMinimumWidth
            ) { index in
                localLibrary.selectImage(at: index)
            } onQuickLook: { image in
                LocalQuickLookController.shared.open(url: image.url)
            } onShowInfo: { image in
                toggleInfo(for: image)
            }
            .background(.background)
            .ignoresSafeArea(.container, edges: .top)
        }
    }

    private var contentLayout: LocalContentLayout {
        preferences.layout
    }

    private var imageSortField: LocalImageSortField {
        preferences.sortField
    }

    private var imageSortDirection: LocalImageSortDirection {
        preferences.sortDirection
    }

    private var inspectedMetadata: LocalImageMetadata? {
        guard let infoImage else { return nil }
        return metadataByImageID[infoImage.id]
    }

    private var filteredImages: [LocalImageItem] {
        guard !preferences.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return localLibrary.selectedImages
        }
        return filteredImagesWithOriginalIndex.map(\.image)
    }

    private var filteredImagesWithOriginalIndex: [(originalIndex: Int, image: LocalImageItem)] {
        let query = preferences.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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
        if preferences.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
        Button("设置为桌面壁纸") {
            LocalDesktopWallpaperSetter.setDesktopWallpaper(image.url)
        }
        Divider()
        Button("在 Finder 中显示") {
            NSWorkspace.shared.activateFileViewerSelecting([image.url])
        }
        Button("快速预览") {
            LocalQuickLookController.shared.open(url: image.url)
        }
        Button("详细信息") {
            toggleInfo(for: image)
        }
        Button("复制路径") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(image.url.path, forType: .string)
        }
        Button("打开文件") {
            NSWorkspace.shared.open(image.url)
        }
    }

    private func toggleInfo(for image: LocalImageItem) {
        if infoImage?.id == image.id {
            infoImage = nil
        } else {
            infoImage = image
        }
    }

    private func loadMetadata(for images: [LocalImageItem]) async {
        let metadata = await LocalImageMetadataService.loadMetadata(for: images)
        guard !Task.isCancelled else { return }
        metadataByImageID = metadata
    }

    private func monitorFileAvailability() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            let images = localLibrary.selectedImages
            let availability = await LocalImageMetadataService.loadAvailability(for: images)

            guard !Task.isCancelled else { return }
            for (id, fileExists) in availability {
                guard let metadata = metadataByImageID[id], metadata.fileExists != fileExists else { continue }
                metadataByImageID[id] = LocalImageMetadata(
                    fileSize: metadata.fileSize,
                    modifiedDate: metadata.modifiedDate,
                    pixelWidth: metadata.pixelWidth,
                    pixelHeight: metadata.pixelHeight,
                    fileExists: fileExists
                )
            }
        }
    }

    private func chooseAndImportRootFolder() {
        guard let folderURL = LocalLibraryImportService.chooseFolder() else { return }
        localLibrary.importRootFolder(folderURL)
    }
}
