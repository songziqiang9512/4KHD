import AppKit
import SwiftUI

private enum LocalContentLayout: String {
    case list
    case grid
}

/// 三段式中部内容栏 —— 显示当前所选本地目录里的所有图片，
/// selection 由 `LocalLibraryStore.selectedImageIndex` 桥接。
struct LocalImageContentList: View {
    @Environment(LocalLibraryStore.self) private var localLibrary
    @AppStorage("com.songziqiang.4khd.localContentLayout.v1") private var contentLayoutRaw = LocalContentLayout.grid.rawValue
    @State private var searchText = ""

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
                Button {
                    localLibrary.refreshSelectedRoot()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新本地目录")
                .disabled(localLibrary.selectedFolder == nil || localLibrary.isScanning)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let folder = localLibrary.selectedFolder {
                        NSWorkspace.shared.activateFileViewerSelecting([folder.url])
                    }
                } label: {
                    Image(systemName: "folder")
                }
                .help("在 Finder 中显示")
                .disabled(localLibrary.selectedFolder == nil)
            }
        }
    }

    @ViewBuilder
    private func content(for folder: LocalFolderNode) -> some View {
        switch contentLayout {
        case .list:
            List(selection: selectionBinding) {
                ForEach(filteredImagesWithOriginalIndex, id: \.image.id) { item in
                    LocalImageRow(image: item.image, index: item.originalIndex + 1)
                        .tag(item.image.id)
                }
            }
            .listStyle(.inset)
        case .grid:
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 136, maximum: 136), spacing: 12)], spacing: 12) {
                    ForEach(filteredImagesWithOriginalIndex, id: \.image.id) { item in
                        LocalImageGridCard(
                            image: item.image,
                            index: item.originalIndex + 1,
                            isSelected: localLibrary.selectedImage?.id == item.image.id
                        ) {
                            localLibrary.selectImage(at: item.originalIndex)
                        }
                    }
                }
                .padding(12)
            }
            .background(.background)
        }
    }

    private var contentLayout: LocalContentLayout {
        LocalContentLayout(rawValue: contentLayoutRaw) ?? .grid
    }

    private var filteredImages: [LocalImageItem] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return localLibrary.selectedImages
        }
        return filteredImagesWithOriginalIndex.map(\.image)
    }

    private var filteredImagesWithOriginalIndex: [(originalIndex: Int, image: LocalImageItem)] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = localLibrary.selectedImages
        guard !query.isEmpty else {
            return Array(images.enumerated()).map { ($0.offset, $0.element) }
        }
        return images.enumerated().compactMap { index, image in
            image.title.localizedStandardContains(query) ? (index, image) : nil
        }
    }

    private func navigationSubtitle(for folder: LocalFolderNode) -> String {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(folder.images.count) 张"
        }
        return "\(filteredImages.count) / \(folder.images.count) 张"
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
    let index: Int

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
                    .lineLimit(2)
                Text("#\(index)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

private struct LocalImageGridCard: View {
    let image: LocalImageItem
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void

    private let cardWidth: CGFloat = 136
    private let thumbnailHeight: CGFloat = 176

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 7) {
                RemoteImageView(url: image.url, contentMode: .fill, priority: .utility, localMaxPixelSize: 220) {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                }
                .frame(width: cardWidth - 14, height: thumbnailHeight)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 4) {
                    Text(image.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.leading)
                        .frame(height: 34, alignment: .topLeading)

                    Text("#\(index)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: cardWidth - 14, alignment: .leading)
            }
            .padding(7)
            .frame(width: cardWidth, height: 240, alignment: .topLeading)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.14), lineWidth: isSelected ? 1.5 : 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
