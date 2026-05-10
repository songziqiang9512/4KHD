import AppKit
import Nuke
import SwiftUI
import UniformTypeIdentifiers

struct GalleryWorkspaceView: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SectionRail()
                    .frame(width: 128)

                GalleryListPane()
                    .frame(width: 330)

                Divider()

                ImageDetailPane()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            FullscreenImageViewerOverlay()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            library.refreshFromNetwork()
        }
    }
}

private struct SectionRail: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("4KHD")
                .font(.title2.weight(.bold))
                .padding(.bottom, 12)

            ForEach(GallerySection.allCases) { section in
                Button {
                    library.section = section
                } label: {
                    HStack {
                        Text(section.title)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 34)
                    .background(library.section == section ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text(library.isRefreshingList ? "线上刷新中" : "线上数据")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct GalleryListPane: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(library.activeSearchQuery.map { "搜索：\($0)" } ?? library.section.title)
                        .font(.headline)
                    Text("\(library.visibleItems.count) / \(library.allItems.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("搜索", text: $library.searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .onSubmit {
                            library.submitSearch()
                        }
                    if library.activeSearchQuery != nil || !library.searchText.isEmpty {
                        Button {
                            library.clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("清空搜索")
                    }
                }
                .padding(.horizontal, 8)
                .frame(width: 160, height: 28)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
            }
            .padding(12)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(library.visibleItems) { item in
                        GalleryRow(item: item, isSelected: library.selectedItem?.id == item.id)
                            .onTapGesture {
                                library.select(item)
                            }
                            .onAppear {
                                if item.id == library.visibleItems.last?.id {
                                    library.loadMoreListIfNeeded()
                                }
                            }
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("list-bottom-\(library.allItems.count)")
                        .onAppear {
                            if library.visibleItems.count >= library.allItems.count {
                                library.loadMoreListIfNeeded()
                            }
                        }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .background(
                    GeometryReader { proxy in
                        let frame = proxy.frame(in: .named("GalleryListScroll"))
                        Color.clear
                            .onChange(of: frame.minY) { _, _ in
                                if frame.maxY - viewportHeight < 220 {
                                    library.loadMoreListIfNeeded()
                                }
                            }
                    }
                )
            }
            .coordinateSpace(name: "GalleryListScroll")
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { viewportHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, value in viewportHeight = value }
                }
            )
        }
    }
}

private struct GalleryRow: View {
    @EnvironmentObject private var library: LibraryStore

    let item: GalleryItem
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PosterWebImage(url: item.coverURL, contentMode: .fill)
                .frame(width: 76, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    KindBadge(kind: item.kind)
                    Text("\(item.imageCount) 张")
                    Text("\(item.pageCount) 页")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Text(item.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(3)

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    if library.isFavorite(item) {
                        Label("已收藏", systemImage: "bookmark.fill")
                    }

                    if library.isCached(item) {
                        Label("已缓存", systemImage: "externaldrive.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1))
    }
}

private struct ImageDetailPane: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var displayedImageURL: URL?
    @State private var saveMessage = ""
    @State private var isDetailReady = false
    @State private var detailFailed = false
    @State private var detailResetToken = UUID()
    @State private var saveTask: ImageTask?

    var body: some View {
        if let item = library.selectedItem, let slot = library.selectedSlot {
            VStack(spacing: 0) {
                header(item: item, slot: slot)

                ZStack {
                    Color(red: 0.06, green: 0.06, blue: 0.065)

                    GeometryReader { proxy in
                        DetailImageResolverView(
                            pageURL: slot.pageURL,
                            onResolvedPage: { page in
                                Task { @MainActor in
                                    library.registerResolvedPage(page)
                                }
                            },
                            onFailure: {
                                detailFailed = true
                                isDetailReady = true
                            }
                        )
                        .frame(width: 1, height: 1)
                        .opacity(0.001)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                        ZoomableImageCanvas(url: slot.knownURL, resetToken: detailResetToken) {
                            DetailPlaceholder(kind: detailFailed ? .failed : .loading)
                        } onDisplayed: {
                            displayedImageURL = slot.knownURL
                            isDetailReady = true
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
                }

                Filmstrip(slots: library.loadedImageSlots, selectedIndex: library.selectedImageIndex) { index in
                    library.selectImage(at: index)
                } onReachedEnd: {
                    library.ensureNextDetailPageLoaded(reason: .filmstripReachedEnd)
                }
            }
            .onChange(of: item.id) { _, _ in
                displayedImageURL = nil
                saveMessage = ""
                isDetailReady = false
                detailFailed = false
                RemoteImagePipeline.shared.stopDetailPrefetching()
            }
            .onChange(of: slot.id) { _, _ in
                displayedImageURL = nil
                saveMessage = ""
                isDetailReady = false
                detailFailed = false
                RemoteImagePipeline.shared.prefetchDetailImages(library.upcomingKnownImageURLs)
            }
            .onAppear {
                RemoteImagePipeline.shared.prefetchDetailImages(library.upcomingKnownImageURLs)
            }
        } else {
            ContentUnavailableView("没有可显示内容", systemImage: "photo")
        }
    }

    private func header(item: GalleryItem, slot: ImageSlot) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    KindBadge(kind: item.kind)
                    Text("\(item.imageCount) 张")
                    Text("\(item.pageCount) 页")
                    Text("#\(slot.displayIndex)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if !saveMessage.isEmpty {
                Text(saveMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                library.isFullscreenViewerPresented = true
            } label: {
                Label("全屏", systemImage: "arrow.up.left.and.arrow.down.right")
            }

            Button {
                detailResetToken = UUID()
            } label: {
                Label("实际大小", systemImage: "1.magnifyingglass")
            }

            Button {
                library.toggleFavorite(for: item)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: library.isFavorite(item) ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(library.isFavorite(item) ? Color.red : Color.primary)
                    Text("收藏")
                }
            }

            Button {
                NSWorkspace.shared.open(item.detailURL)
            } label: {
                Label("原网页", systemImage: "safari")
            }
            .help(item.detailURL.absoluteString)

            Button {
                saveCurrentImage(item: item, slot: slot)
            } label: {
                Label("保存", systemImage: "square.and.arrow.down")
            }
            .disabled(slot.knownURL == nil)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial)
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

private struct DetailPlaceholder: View {
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

private struct FullscreenImageViewerOverlay: View {
    @EnvironmentObject private var library: LibraryStore

    @State private var resetToken = UUID()
    @State private var viewerDetailFailed = false

    var body: some View {
        if library.isFullscreenViewerPresented {
            ZStack {
                Color.black.ignoresSafeArea()

                if let item = library.selectedItem, let slot = library.selectedSlot {
                    GeometryReader { proxy in
                        DetailImageResolverView(
                            pageURL: slot.pageURL,
                            onResolvedPage: { page in
                                Task { @MainActor in
                                    library.registerResolvedPage(page)
                                    viewerDetailFailed = false
                                }
                            },
                            onFailure: {
                                viewerDetailFailed = true
                            }
                        )
                        .frame(width: 1, height: 1)
                        .opacity(0.001)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                        ZoomableImageCanvas(url: slot.knownURL, resetToken: resetToken) {
                            DetailPlaceholder(kind: viewerDetailFailed ? .failed : .loading)
                        } onDisplayed: {
                            viewerDetailFailed = false
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                    .clipped()

                    VStack(spacing: 0) {
                        fullscreenHeader(item: item, slot: slot)
                        Spacer()
                        Filmstrip(slots: library.loadedImageSlots, selectedIndex: library.selectedImageIndex) { index in
                            library.selectImage(at: index)
                        } onReachedEnd: {
                            library.ensureNextDetailPageLoaded(reason: .filmstripReachedEnd)
                        }
                    }

                    HStack {
                        StepButton(systemName: "chevron.left") { library.stepImage(-1) }
                            .disabled(library.selectedImageIndex == 0)
                        Spacer()
                        StepButton(systemName: "chevron.right") { library.stepImage(1) }
                    }
                    .padding(.horizontal, 24)
                } else {
                    ContentUnavailableView("没有可显示内容", systemImage: "photo")
                }
            }
            .transition(.opacity)
            .zIndex(20)
            .onChange(of: library.selectedSlot?.id) { _, _ in
                viewerDetailFailed = false
                resetToken = UUID()
            }
            .onExitCommand {
                library.isFullscreenViewerPresented = false
            }
        }
    }

    private func fullscreenHeader(item: GalleryItem, slot: ImageSlot) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("#\(slot.displayIndex) / \(item.imageCount) 张")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                resetToken = UUID()
            } label: {
                Label("实际大小", systemImage: "1.magnifyingglass")
            }

            Button {
                library.isFullscreenViewerPresented = false
            } label: {
                Label("关闭", systemImage: "xmark")
            }
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}

private struct ZoomableImageCanvas<Placeholder: View>: View {
    let url: URL?
    let resetToken: UUID
    @ViewBuilder let placeholder: () -> Placeholder
    let onDisplayed: () -> Void

    @State private var zoomScale: CGFloat = 1
    @State private var lastMagnification: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            RemoteImageView(url: url, contentMode: .fit, priority: .userInitiated, onLoaded: onDisplayed) {
                placeholder()
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .scaleEffect(max(0.35, zoomScale))
            .offset(panOffset)
            .contentShape(Rectangle())
            .overlay {
                TrackpadPanView { delta in
                    guard zoomScale > 1 else { return }
                    let proposed = CGSize(
                        width: panOffset.width + delta.width,
                        height: panOffset.height + delta.height
                    )
                    panOffset = clampedPanOffset(proposed, in: proxy.size)
                    dragStartOffset = panOffset
                }
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = value / lastMagnification
                        zoomScale = min(max(zoomScale * delta, 0.35), 5)
                        lastMagnification = value
                        panOffset = clampedPanOffset(panOffset, in: proxy.size)
                    }
                    .onEnded { _ in
                        lastMagnification = 1
                        panOffset = clampedPanOffset(panOffset, in: proxy.size)
                        dragStartOffset = panOffset
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let proposed = CGSize(
                            width: dragStartOffset.width + value.translation.width,
                            height: dragStartOffset.height + value.translation.height
                        )
                        panOffset = clampedPanOffset(proposed, in: proxy.size)
                    }
                    .onEnded { _ in
                        panOffset = clampedPanOffset(panOffset, in: proxy.size)
                        dragStartOffset = panOffset
                    }
            )
        }
        .clipped()
        .onChange(of: url) { _, _ in resetView() }
        .onChange(of: resetToken) { _, _ in resetView() }
        .animation(.snappy(duration: 0.18), value: zoomScale)
    }

    private func resetView() {
        zoomScale = 1
        lastMagnification = 1
        panOffset = .zero
        dragStartOffset = .zero
    }

    private func clampedPanOffset(_ offset: CGSize, in size: CGSize) -> CGSize {
        guard zoomScale > 1 else { return .zero }
        let maxX = max(size.width * (zoomScale - 1) / 2, 0)
        let maxY = max(size.height * (zoomScale - 1) / 2, 0)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }
}

private struct TrackpadPanView: NSViewRepresentable {
    let onPan: (CGSize) -> Void

    func makeNSView(context: Context) -> NSView {
        ScrollCatcherView(onPan: onPan)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ScrollCatcherView)?.onPan = onPan
    }

    private final class ScrollCatcherView: NSView {
        var onPan: (CGSize) -> Void

        init(onPan: @escaping (CGSize) -> Void) {
            self.onPan = onPan
            super.init(frame: .zero)
            wantsLayer = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func scrollWheel(with event: NSEvent) {
            let horizontalDelta = event.scrollingDeltaX
            let verticalDelta = event.scrollingDeltaY

            if abs(horizontalDelta) > abs(verticalDelta) {
                onPan(CGSize(width: horizontalDelta, height: 0))
            } else {
                onPan(CGSize(width: 0, height: verticalDelta))
            }
        }

        override func mouseDown(with event: NSEvent) {
            nextResponder?.mouseDown(with: event)
        }

        override func mouseDragged(with event: NSEvent) {
            nextResponder?.mouseDragged(with: event)
        }

        override func mouseUp(with event: NSEvent) {
            nextResponder?.mouseUp(with: event)
        }
    }
}

private struct Filmstrip: View {
    let slots: [ImageSlot]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let onReachedEnd: () -> Void
    @State private var viewportWidth: CGFloat = 0

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
                ForEach(slots.indices, id: \.self) { index in
                    let slot = slots[index]
                    Button {
                        onSelect(index)
                    } label: {
                        ZStack(alignment: .bottomLeading) {
                            SlotThumbnail(slot: slot)
                            Text("#\(slot.displayIndex)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.black.opacity(0.5), in: Capsule())
                                .padding(5)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selectedIndex == index ? Color.accentColor : Color.white.opacity(0.15), lineWidth: selectedIndex == index ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .named("FilmstripScroll"))
                    Color.clear
                        .onChange(of: frame.minX) { _, _ in
                            if frame.width > viewportWidth,
                               frame.maxX - viewportWidth < 180 {
                                onReachedEnd()
                            }
                        }
                }
            )
        }
        .coordinateSpace(name: "FilmstripScroll")
        .frame(height: 120)
        .background(Color(red: 0.08, green: 0.08, blue: 0.085))
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { viewportWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, value in viewportWidth = value }
            }
        )
    }
}

private struct PosterWebImage: View {
    let url: URL?
    let contentMode: ContentMode

    var body: some View {
        RemoteImageView(url: url, contentMode: contentMode, priority: .background) {
            Rectangle()
                .fill(Color.white.opacity(url == nil ? 0.08 : 0.11))
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }
}

private struct SlotThumbnail: View {
    let slot: ImageSlot

    var body: some View {
        RemoteImageView(url: slot.knownURL, contentMode: .fill, priority: .utility) {
            Rectangle()
                .fill(slot.knownURL == nil ? Color.white.opacity(0.06) : Color.white.opacity(0.11))
                .overlay(Image(systemName: "photo").font(.caption).foregroundStyle(.secondary))
        }
            .frame(width: 72, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct KindBadge: View {
    let kind: ContentKind

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
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

private struct StepButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 70)
                .background(.black.opacity(0.36), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
