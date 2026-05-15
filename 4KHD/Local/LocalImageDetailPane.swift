import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LocalImageDetailPane: View {
    @Environment(LocalLibraryStore.self) private var localLibrary
    @Environment(ImmersiveController.self) private var immersive
    @AppStorage("com.songziqiang.4khd.showsFilmstrip.v1") private var showsFilmstrip = true
    @State private var resetToken = UUID()
    @State private var saveMessage = ""
    @State private var isFilmstripReady = false
    @State private var infoImage: LocalImageItem?
    @State private var metadataByImageID: [LocalImageItem.ID: LocalImageMetadata] = [:]

    var body: some View {
        Group {
            if let folder = localLibrary.selectedFolder, let image = localLibrary.selectedImage {
                content(folder: folder, image: image)
            } else {
                ContentUnavailableView("没有可显示图片", systemImage: "photo")
            }
        }
    }

    @ViewBuilder
    private func content(folder: LocalFolderNode, image: LocalImageItem) -> some View {
        ZStack {
            Color.black
                .ignoresSafeArea(edges: [.horizontal, .bottom])

            GeometryReader { proxy in
                let maxPixelSize = max(proxy.size.width, proxy.size.height) * 2
                ZoomableImageCanvas(
                    url: image.url,
                    resetToken: resetToken,
                    contentInsets: EdgeInsets(),
                    localMaxPixelSize: maxPixelSize
                ) {
                    DetailPlaceholder(kind: .loading)
                } onDisplayed: {
                    isFilmstripReady = true
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .clipped()

            HStack {
                StepButton(systemName: "chevron.left") { localLibrary.stepImage(-1) }
                    .disabled(localLibrary.selectedImageIndex == 0)
                Spacer()
                StepButton(systemName: "chevron.right") { localLibrary.stepImage(1) }
                    .disabled(localLibrary.selectedImageIndex >= localLibrary.selectedImages.count - 1)
            }
            .padding(.horizontal, 18)

            KeyDownCatcher { event in
                handleKeyDown(event)
            }
            .frame(width: 0, height: 0)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    if let status = saveStatus {
                        DetailStatusBadge(kind: status.kind, text: status.text)
                            .padding(16)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsFilmstrip && isFilmstripReady {
                LocalFilmstrip(images: localLibrary.selectedImages, selectedIndex: localLibrary.selectedImageIndex) { index in
                    localLibrary.selectImage(at: index)
                }
            }
        }
        .navigationTitle(folder.title)
        .navigationSubtitle("\(localLibrary.selectedImageIndex + 1) / \(localLibrary.selectedImages.count) · \(image.title)")
        .toolbar { toolbarContent(image: image) }
        .overlay(alignment: .topTrailing) {
            LocalImageInspectorOverlay(
                image: infoImage,
                metadata: inspectedMetadata,
                onDismiss: { infoImage = nil }
            )
        }
        .task(id: folder.id) {
            await loadMetadata(for: localLibrary.selectedImages)
        }
        .onExitCommand {
            if immersive.isImmersive { immersive.toggle() }
        }
        .onChange(of: image.id) { _, _ in
            resetToken = UUID()
            saveMessage = ""
            isFilmstripReady = false
            LocalQuickLookController.shared.syncVisible(url: image.url)
            if infoImage != nil {
                infoImage = image
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let command = DetailKeyCommand(event: event) else { return false }
        switch command {
        case .previous:
            localLibrary.stepImage(-1)
            return true
        case .next:
            localLibrary.stepImage(1)
            return true
        case .quickLook:
            if let image = localLibrary.selectedImage {
                LocalQuickLookController.shared.open(url: image.url)
                return true
            }
            return false
        case .toggleImmersive:
            immersive.toggle()
            return true
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent(image: LocalImageItem) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                resetToken = UUID()
            } label: {
                Label("实际大小", systemImage: "1.magnifyingglass")
            }
            .keyboardShortcut("0", modifiers: [.command])
            .help("实际大小")

            Button {
                immersive.toggle()
            } label: {
                Label("全屏", systemImage: immersive.isImmersive
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
            }
            .help(immersive.isImmersive ? "退出大图模式" : "进入大图模式")

            Button {
                showsFilmstrip.toggle()
            } label: {
                Label(showsFilmstrip ? "隐藏缩略图" : "显示缩略图",
                      systemImage: showsFilmstrip ? "rectangle.bottomthird.inset.filled" : "rectangle")
            }
            .help(showsFilmstrip ? "隐藏下方缩略图" : "显示下方缩略图")

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([image.url])
            } label: {
                Label("Finder", systemImage: "folder")
            }
            .help("在 Finder 中显示")

            Button {
                LocalQuickLookController.shared.open(url: image.url)
            } label: {
                Label("快速预览", systemImage: "eye")
            }
            .help("快速预览")

            Button {
                infoImage = image
            } label: {
                Label("详细信息", systemImage: "info.circle")
            }
            .help("详细信息")

            Button {
                saveImage(image)
            } label: {
                Label("保存", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: [.command])
            .help("保存副本")
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
                    pixelHeight: pixelSize?.height,
                    fileExists: FileManager.default.fileExists(atPath: image.url.path)
                )
            }
            return result
        }.value

        guard !Task.isCancelled else { return }
        metadataByImageID = metadata
    }

    private var saveStatus: (kind: DetailStatusBadge.Kind, text: String)? {
        if saveMessage == "已保存" {
            return (.saved, saveMessage)
        }
        if saveMessage == "保存失败" {
            return (.failed, saveMessage)
        }
        return nil
    }

    private var inspectedMetadata: LocalImageMetadata? {
        guard let infoImage else { return nil }
        return metadataByImageID[infoImage.id]
    }

    private func saveImage(_ image: LocalImageItem) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.image]
        panel.nameFieldStringValue = image.title
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let target = panel.url else { return }

        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: image.url, to: target)
            saveMessage = "已保存"
        } catch {
            saveMessage = "保存失败"
        }
    }
}

struct LocalFilmstrip: View {
    let images: [LocalImageItem]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    @State private var viewportWidth: CGFloat = 0
    @State private var lastBatchStart: Int = -1
    private let tilePitch: CGFloat = 82

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(images.indices, id: \.self) { index in
                        let image = images[index]
                        Button {
                            onSelect(index)
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                LocalImageThumbnail(url: image.url)
                                Text("#\(index + 1)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(.regularMaterial, in: Capsule())
                                    .padding(5)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(selectedIndex == index ? Color.accentColor : Color.clear,
                                            lineWidth: selectedIndex == index ? 2 : 0)
                            )
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .frame(height: 112)
            .background(.background)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { viewportWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, value in viewportWidth = value }
                }
            )
            .onChange(of: selectedIndex) { _, index in
                guard images.indices.contains(index) else { return }
                let tilesPerBatch = max(Int((viewportWidth - 28) / tilePitch), 1)
                let batchStart = (index / tilesPerBatch) * tilesPerBatch
                guard batchStart != lastBatchStart else { return }
                lastBatchStart = batchStart
                withAnimation(.snappy(duration: 0.22)) {
                    scrollProxy.scrollTo(batchStart, anchor: .leading)
                }
            }
            .onAppear {
                guard images.indices.contains(selectedIndex) else { return }
                let tilesPerBatch = max(Int((viewportWidth - 28) / tilePitch), 1)
                lastBatchStart = (selectedIndex / tilesPerBatch) * tilesPerBatch
                scrollProxy.scrollTo(lastBatchStart, anchor: .leading)
            }
        }
    }
}

private struct LocalImageThumbnail: View {
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
