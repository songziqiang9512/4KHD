import AppKit
import Nuke
import SwiftUI
import UniformTypeIdentifiers

/// 线上图集详情面板：主图 + 工具栏 + 底部缩略图条。
/// 通过 `LibraryStore` 读 slot 状态，通过 `ImmersiveController` 切换沉浸模式。
struct ImageDetailPane: View {
    @Environment(LibraryStore.self) private var library
    @Environment(ImmersiveController.self) private var immersive
    @AppStorage("com.songziqiang.4khd.showsFilmstrip.v1") private var showsFilmstrip = true

    @State private var displayedImageURL: URL?
    @State private var saveMessage = ""
    @State private var isDetailReady = false
    @State private var detailFailed = false
    @State private var isFilmstripReady = false
    @State private var detailResetToken = UUID()
    @State private var resolverRetryToken = UUID()
    @State private var saveTask: ImageTask?

    var body: some View {
        Group {
            if let item = library.selectedItem, let slot = library.selectedSlot {
                content(item: item, slot: slot)
            } else {
                ContentUnavailableView("没有可显示内容", systemImage: "photo")
            }
        }
    }

    @ViewBuilder
    private func content(item: GalleryItem, slot: ImageSlot) -> some View {
        ZStack {
            Color.black
                .ignoresSafeArea(edges: [.horizontal, .bottom])

            GeometryReader { proxy in
                DetailImageResolverView(
                    pageURL: slot.pageURL,
                    retryToken: resolverRetryToken,
                    onResolvedPage: { page in
                        Task { @MainActor in
                            library.registerResolvedPage(page)
                        }
                    },
                    onFailure: { failedPageURL in
                        guard failedPageURL == slot.pageURL else { return }
                        detailFailed = true
                        isDetailReady = true
                        isFilmstripReady = true
                    }
                )
                .frame(width: 1, height: 1)
                .opacity(0.001)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                ZoomableImageCanvas(
                    url: slot.knownURL,
                    resetToken: detailResetToken,
                    contentInsets: EdgeInsets()
                ) {
                    DetailPlaceholder(
                        kind: detailFailed ? .failed : .loading,
                        onRetry: detailFailed ? { retryCurrentPage() } : nil,
                        onOpenOriginal: detailFailed ? { NSWorkspace.shared.open(slot.pageURL) } : nil
                    )
                } onDisplayed: {
                    displayedImageURL = slot.knownURL
                    isDetailReady = true
                    isFilmstripReady = true
                    detailFailed = false
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .clipped()

            HStack {
                StepButton(systemName: "chevron.left") { library.stepImage(-1) }
                    .disabled(library.selectedImageIndex == 0)
                Spacer()
                StepButton(systemName: "chevron.right") { library.stepImage(1) }
            }
            .padding(.horizontal, 18)

            VStack {
                Spacer()
                HStack {
                    Text("\(slot.displayIndex) / \(max(item.imageCount, library.loadedImageSlots.count))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(16)
                    Spacer()
                    if let status = detailStatusText {
                        DetailStatusBadge(kind: status.kind, text: status.text)
                            .padding(16)
                    }
                }
            }

            KeyDownCatcher { event in
                handleKeyDown(event)
            }
            .frame(width: 0, height: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsFilmstrip && isFilmstripReady {
                Filmstrip(slots: library.loadedImageSlots, selectedIndex: library.selectedImageIndex) { index in
                    library.selectImage(at: index)
                } onReachedEnd: {
                    library.ensureNextDetailPageLoaded(reason: .filmstripReachedEnd)
                }
            }
        }
        .navigationTitle(item.title)
        .navigationSubtitle("\(slot.displayIndex) / \(max(item.imageCount, library.loadedImageSlots.count))")
        .toolbar { detailToolbar(item: item, slot: slot) }
        .onExitCommand {
            if immersive.isImmersive { immersive.toggle() }
        }
        .onChange(of: item.id) { _, _ in
            displayedImageURL = nil
            saveMessage = ""
            isDetailReady = false
            isFilmstripReady = false
            detailFailed = false
            resolverRetryToken = UUID()
            RemoteImagePipeline.shared.stopDetailPrefetching()
        }
        .onChange(of: slot.id) { _, _ in
            displayedImageURL = nil
            saveMessage = ""
            isDetailReady = false
            detailFailed = false
            resolverRetryToken = UUID()
            RemoteImagePipeline.shared.prefetchDetailImages(library.upcomingKnownImageURLs)
        }
        .onAppear {
            RemoteImagePipeline.shared.prefetchDetailImages(library.upcomingKnownImageURLs)
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let command = DetailKeyCommand(event: event) else { return false }
        switch command {
        case .previous:
            library.stepImage(-1)
            return true
        case .next:
            library.stepImage(1)
            return true
        case .quickLook:
            library.stepImage(1)
            return true
        case .toggleImmersive:
            immersive.toggle()
            return true
        }
    }

    private func retryCurrentPage() {
        detailFailed = false
        isDetailReady = false
        resolverRetryToken = UUID()
    }

    @ToolbarContentBuilder
    private func detailToolbar(item: GalleryItem, slot: ImageSlot) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                library.toggleFavorite(for: item)
            } label: {
                Label("收藏", systemImage: library.isFavorite(item) ? "bookmark.fill" : "bookmark")
            }
            .keyboardShortcut("d", modifiers: [.command])
            .help(library.isFavorite(item) ? "取消收藏" : "收藏")

            Button {
                detailResetToken = UUID()
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
                NSWorkspace.shared.open(item.detailURL)
            } label: {
                Label("原网页", systemImage: "safari")
            }
            .help("打开原网页")

            Button {
                saveCurrentImage(item: item, slot: slot)
            } label: {
                Label("保存", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(slot.knownURL == nil)
            .help("保存")
        }
    }

    private var detailStatusText: (kind: DetailStatusBadge.Kind, text: String)? {
        if detailFailed {
            return (.failed, "解析失败")
        }
        if saveMessage == "保存中" {
            return (.saving, saveMessage)
        }
        if saveMessage == "已保存" {
            return (.saved, saveMessage)
        }
        if saveMessage == "保存失败" {
            return (.failed, saveMessage)
        }
        if !isDetailReady {
            return (.resolving, "解析中")
        }
        if library.prefetchPageURL != nil {
            return (.prefetching, "预取下一页")
        }
        return nil
    }

    private func saveCurrentImage(item: GalleryItem, slot: ImageSlot) {
        guard let imageURL = slot.knownURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.image]
        panel.nameFieldStringValue = "\(item.id)-\(slot.displayIndex).jpg"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let target = panel.url else { return }

        saveMessage = "保存中"
        saveTask?.cancel()
        let request = RemoteImagePipeline.shared.request(for: imageURL, priority: .veryHigh)
        saveTask = RemoteImagePipeline.shared.loadData(with: request) { data in
            guard let data else {
                saveMessage = "保存失败"
                return
            }
            do {
                try data.write(to: target, options: .atomic)
                saveMessage = "已保存"
            } catch {
                saveMessage = "保存失败"
            }
        }
    }
}
