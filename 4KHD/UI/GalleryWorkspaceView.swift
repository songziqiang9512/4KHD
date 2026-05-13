import AppKit
import Nuke
import SwiftUI
import UniformTypeIdentifiers

struct GalleryContentList: View {
    @Environment(LibraryStore.self) private var library
    @AppStorage("com.songziqiang.4khd.favoriteAuthorOverrides.v1") private var favoriteAuthorOverridesJSON = "{}"
    @State private var expandedFavoriteAuthorIDs = Set<String>()

    private var selectionBinding: Binding<GalleryItem.ID?> {
        Binding(
            get: { library.selectedItemID },
            set: { newValue in
                guard let newValue,
                      let item = library.allItems.first(where: { $0.id == newValue }) else { return }
                // 避免在 view update 周期内直接写 @Published（会触发
                // "Publishing changes from within view updates" 警告）
                DispatchQueue.main.async {
                    library.select(item)
                }
            }
        )
    }

    var body: some View {
        // shadow 一份 @Bindable 以便 .searchable(text:) 用 $library.searchText
        @Bindable var library = library
        return List(selection: selectionBinding) {
            if shouldGroupFavorites {
                ForEach(favoriteAuthorGroups) { group in
                    Section {
                        if expandedFavoriteAuthorIDs.contains(group.id) {
                            ForEach(group.items) { item in
                                GalleryRow(item: item)
                                    .tag(item.id)
                                    .contextMenu { favoriteMoveMenu(for: item, currentGroup: group) }
                            }
                        }
                    } header: {
                        FavoriteAuthorSectionHeader(
                            group: group,
                            isExpanded: expandedFavoriteAuthorIDs.contains(group.id)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { toggleFavoriteGroup(group.id) }
                        .contextMenu {
                            Button("重命名目录") { renameFavoriteGroup(group) }
                        }
                        .onAppear {
                            if group.id == favoriteAuthorGroups.last?.id {
                                library.loadMoreListIfNeeded()
                            }
                        }
                    }
                }
            } else {
                ForEach(library.visibleItems) { item in
                    GalleryRow(item: item)
                        .tag(item.id)
                        .onAppear {
                            if item.id == library.visibleItems.last?.id {
                                library.loadMoreListIfNeeded()
                            }
                        }
                }
            }

            if library.isRefreshingList || library.canLoadMoreList || !library.visibleItems.isEmpty {
                ListFooterStatus()
                    .listRowSeparator(.hidden)
                    .onAppear {
                        if library.canLoadMoreList { library.loadMoreListIfNeeded() }
                    }
            }
        }
        .listStyle(.inset)
        .searchable(text: $library.searchText, placement: .toolbar, prompt: "搜索 4KHD")
        .onSubmit(of: .search) { library.submitSearch() }
        .onChange(of: library.searchText) { _, value in
            if value.isEmpty && library.activeSearchQuery != nil { library.clearSearch() }
        }
        .navigationTitle(library.activeSearchQuery.map { "搜索：\($0)" } ?? library.section.title)
        .navigationSubtitle("\(library.visibleItems.count) / \(library.allItems.count)")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    library.refreshFromNetwork()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])
                .help("刷新")
                .disabled(library.isRefreshingList)
            }
        }
        .onChange(of: library.section) { _, section in
            if section != .favorites {
                expandedFavoriteAuthorIDs.removeAll()
            }
        }
    }

    private var shouldGroupFavorites: Bool {
        library.section == .favorites && library.activeSearchQuery == nil
    }

    private var favoriteAuthorGroups: [FavoriteAuthorGroup] {
        let grouped = groupedFavoriteItems()
        return grouped
            .map { author, items in
                FavoriteAuthorGroup(author: author, items: items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
            }
            .sorted { lhs, rhs in
                lhs.author.localizedStandardCompare(rhs.author) == .orderedAscending
            }
    }

    private func toggleFavoriteGroup(_ id: String) {
        if expandedFavoriteAuthorIDs.contains(id) {
            expandedFavoriteAuthorIDs.remove(id)
        } else {
            expandedFavoriteAuthorIDs.insert(id)
        }
    }

    @ViewBuilder
    private func favoriteMoveMenu(for item: GalleryItem, currentGroup: FavoriteAuthorGroup) -> some View {
        let targetGroups = favoriteAuthorGroups.filter { $0.id != currentGroup.id }
        if !targetGroups.isEmpty {
            Text("移动到目录")
            ForEach(targetGroups) { group in
                Button(group.author) {
                    setFavoriteAuthorOverride(group.author, for: item)
                    expandedFavoriteAuthorIDs.insert(group.id)
                }
            }
        }

        if favoriteAuthorOverrides[item.detailURL.absoluteString] != nil {
            Button("恢复自动分类") {
                removeFavoriteAuthorOverride(for: item)
            }
        }
    }

    private func groupedFavoriteItems() -> [String: [GalleryItem]] {
        let overrides = favoriteAuthorOverrides
        let automaticItems = library.visibleItems.filter { overrides[$0.detailURL.absoluteString] == nil }
        var grouped = FavoriteAuthorNameParser.group(automaticItems)

        for item in library.visibleItems {
            guard let override = overrides[item.detailURL.absoluteString] else { continue }
            let author = normalizedFavoriteAuthorOverride(override)
            grouped[author, default: []].append(item)
        }
        return grouped
    }

    private var favoriteAuthorOverrides: [String: String] {
        guard let data = favoriteAuthorOverridesJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func setFavoriteAuthorOverride(_ author: String, for item: GalleryItem) {
        var overrides = favoriteAuthorOverrides
        overrides[item.detailURL.absoluteString] = normalizedFavoriteAuthorOverride(author)
        saveFavoriteAuthorOverrides(overrides)
    }

    private func removeFavoriteAuthorOverride(for item: GalleryItem) {
        var overrides = favoriteAuthorOverrides
        overrides[item.detailURL.absoluteString] = nil
        saveFavoriteAuthorOverrides(overrides)
    }

    private func renameFavoriteGroup(_ group: FavoriteAuthorGroup) {
        guard let newAuthor = promptForFavoriteGroupName(currentName: group.author) else { return }
        var overrides = favoriteAuthorOverrides
        for item in group.items {
            overrides[item.detailURL.absoluteString] = newAuthor
        }
        saveFavoriteAuthorOverrides(overrides)
        expandedFavoriteAuthorIDs.remove(group.id)
        expandedFavoriteAuthorIDs.insert(newAuthor.lowercased())
    }

    private func promptForFavoriteGroupName(currentName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "重命名收藏目录"
        alert.informativeText = "目录名会应用到当前目录下的所有收藏图集。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = currentName
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let newAuthor = normalizedFavoriteAuthorOverride(textField.stringValue)
        guard !newAuthor.isEmpty else { return nil }
        return newAuthor
    }

    private func saveFavoriteAuthorOverrides(_ overrides: [String: String]) {
        guard let data = try? JSONEncoder().encode(overrides),
              let json = String(data: data, encoding: .utf8) else { return }
        favoriteAuthorOverridesJSON = json
    }

    private func normalizedFavoriteAuthorOverride(_ author: String) -> String {
        let normalized = author
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "未知作者" : normalized
    }

}

private struct FavoriteAuthorGroup: Identifiable {
    let author: String
    let items: [GalleryItem]

    var id: String {
        author.lowercased()
    }
}

private struct FavoriteAuthorSectionHeader: View {
    let group: FavoriteAuthorGroup
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
            Text(group.author)
                .font(.callout.weight(.semibold))
            Spacer(minLength: 4)
            Text("\(group.items.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private enum FavoriteAuthorNameParser {
    static func group(_ items: [GalleryItem]) -> [String: [GalleryItem]] {
        let itemCandidates = items.map { item in
            (item: item, candidates: authorCandidates(for: item))
        }
        let candidateCounts = Dictionary(
            itemCandidates.flatMap(\.candidates).map { ($0.key, 1) },
            uniquingKeysWith: +
        )
        let displayCounts = Dictionary(
            itemCandidates.flatMap(\.candidates).map { ("\($0.key)\u{1F}\($0.display)", 1) },
            uniquingKeysWith: +
        )

        let keyedGroups = Dictionary(grouping: itemCandidates) { pair in
            bestRepeatedCandidate(in: pair.candidates, counts: candidateCounts)?.key
                ?? pair.candidates.first?.key
                ?? canonicalKey("未知作者")
        }

        var result: [String: [GalleryItem]] = [:]
        for (key, pairs) in keyedGroups {
            let display = bestDisplayName(for: key, candidates: pairs.flatMap(\.candidates), displayCounts: displayCounts)
            result[display, default: []].append(contentsOf: pairs.map(\.item))
        }
        return result
    }

    private struct AuthorCandidate: Hashable {
        let display: String
        let key: String
    }

    private static func authorCandidates(for item: GalleryItem) -> [AuthorCandidate] {
        let source = item.rawTitle.isEmpty ? item.title : item.rawTitle
        let cleaned = removeMetadata(from: source)
        let titleWithoutLeadingTags = removeLeadingCatalogCode(from: removeLeadingBracketTags(from: cleaned))
        var candidates: [String] = []

        if titleWithoutLeadingTags.isEmpty,
           let bracketAuthor = firstMatch(#"^\s*\[([^\]]+)\]"#, in: cleaned) {
            candidates.append(normalized(bracketAuthor))
        }

        candidates.append(contentsOf: separatorCandidates(from: titleWithoutLeadingTags))
        candidates.append(contentsOf: tokenPrefixCandidates(from: titleWithoutLeadingTags))

        return unique(candidates.map(makeCandidate).filter { !$0.key.isEmpty })
    }

    private static func bestRepeatedCandidate(in candidates: [AuthorCandidate], counts: [String: Int]) -> AuthorCandidate? {
        candidates
            .filter { (counts[$0.key] ?? 0) > 1 }
            .sorted { lhs, rhs in
                let lhsCount = counts[lhs.key] ?? 0
                let rhsCount = counts[rhs.key] ?? 0
                if lhsCount != rhsCount {
                    return lhsCount > rhsCount
                }
                if lhs.display.count != rhs.display.count {
                    return lhs.display.count > rhs.display.count
                }
                return lhs.display.localizedStandardCompare(rhs.display) == .orderedAscending
            }
            .first
    }

    private static func bestDisplayName(
        for key: String,
        candidates: [AuthorCandidate],
        displayCounts: [String: Int]
    ) -> String {
        candidates
            .filter { $0.key == key }
            .map(\.display)
            .sorted { lhs, rhs in
                let lhsCount = displayCounts["\(key)\u{1F}\(lhs)"] ?? 0
                let rhsCount = displayCounts["\(key)\u{1F}\(rhs)"] ?? 0
                if lhsCount != rhsCount {
                    return lhsCount > rhsCount
                }
                if lhs.count != rhs.count {
                    return lhs.count < rhs.count
                }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
            .first ?? "未知作者"
    }

    private static func separatorCandidates(from value: String) -> [String] {
        let separators = [" - ", " – ", " — ", " | ", " / ", "：", ": "]
        return separators.compactMap { separator in
            guard let range = value.range(of: separator) else { return nil }
            let prefix = String(value[..<range.lowerBound])
            return normalized(prefix)
        }
    }

    private static func tokenPrefixCandidates(from value: String) -> [String] {
        let tokens = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return ["未知作者"] }

        var kept: [String] = []
        for token in tokens.prefix(4) {
            let cleanedToken = token.trimmingCharacters(in: CharacterSet(charactersIn: ",，.。()（）[]【】"))
            guard !cleanedToken.isEmpty else { continue }
            if isSeparatorToken(cleanedToken) || isLikelySeriesToken(cleanedToken) {
                break
            }
            kept.append(cleanedToken)
            if cleanedToken.contains("(") || cleanedToken.contains("（") {
                break
            }
        }

        let usableTokens = kept.isEmpty ? [tokens[0]] : kept
        return (1...usableTokens.count).map { index in
            normalized(usableTokens.prefix(index).joined(separator: " "))
        }
    }

    private static func removeMetadata(from value: String) -> String {
        value
            .replacingOccurrences(of: #"\[[^\]]*-\d+photos\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeLeadingBracketTags(from value: String) -> String {
        value
            .replacingOccurrences(of: #"^\s*(?:\[[^\]]+\]\s*)+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeLeadingCatalogCode(from value: String) -> String {
        value
            .replacingOccurrences(
                of: #"^\s*(?:[._#-]*\d+(?:\.\d+)?|Vol\.?\s*\d+|No\.?\s*\d+|Part\s*\d+)\s+"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isSeparatorToken(_ token: String) -> Bool {
        ["-", "–", "—", "|", "/", ":", "："].contains(token)
    }

    private static func isLikelySeriesToken(_ token: String) -> Bool {
        token.range(of: #"^(Vol\.?\d*|No\.?\d*|Part\d*|Photo|Photos|写真|圖集|图集|Collection|Set|COS|Cosplay)$"#, options: [.regularExpression, .caseInsensitive]) != nil
            || token.range(of: #"^\d+$"#, options: .regularExpression) != nil
    }

    private nonisolated static func makeCandidate(_ value: String) -> AuthorCandidate {
        let display = normalized(value)
        return AuthorCandidate(display: display, key: canonicalKey(display))
    }

    private nonisolated static func canonicalKey(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"[\s\p{P}\p{S}]+"#, with: "", options: .regularExpression)
    }

    private nonisolated static func normalized(_ value: String) -> String {
        let result = value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "未知作者" : result
    }

    private static func unique(_ values: [AuthorCandidate]) -> [AuthorCandidate] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.key).inserted }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
}

private struct GalleryRow: View {
    @Environment(LibraryStore.self) private var library
    let item: GalleryItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PosterWebImage(url: item.coverURL, contentMode: .fill)
                .frame(width: 64, height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    KindBadge(kind: item.kind)
                    Text("\(item.imageCount) 张 · \(item.pageCount) 页")
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Text(item.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                HStack(spacing: 9) {
                    if library.isFavorite(item) {
                        Image(systemName: "bookmark.fill")
                            .symbolRenderingMode(.hierarchical)
                            .help("已收藏")
                    }
                    if library.isCached(item) {
                        Image(systemName: "externaldrive.fill")
                            .symbolRenderingMode(.hierarchical)
                            .help("已缓存")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

private struct ListFooterStatus: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        HStack(spacing: 8) {
            if library.isRefreshingList {
                ProgressView()
                    .controlSize(.small)
                Text("加载下一页")
            } else if library.canLoadMoreList {
                Image(systemName: "arrow.down")
                Text("继续加载")
            } else if !library.visibleItems.isEmpty {
                Text("已到末尾")
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
    }
}

struct ImageDetailPane: View {
    @Environment(LibraryStore.self) private var library
    @Environment(ImmersiveController.self) private var immersive
    @State private var displayedImageURL: URL?
    @State private var saveMessage = ""
    @State private var isDetailReady = false
    @State private var detailFailed = false
    @State private var detailResetToken = UUID()
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
                .ignoresSafeArea()

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

                ZoomableImageCanvas(
                    url: slot.knownURL,
                    resetToken: detailResetToken,
                    contentInsets: EdgeInsets()
                ) {
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
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Filmstrip(slots: library.loadedImageSlots, selectedIndex: library.selectedImageIndex) { index in
                library.selectImage(at: index)
            } onReachedEnd: {
                library.ensureNextDetailPageLoaded(reason: .filmstripReachedEnd)
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
    }

    @ToolbarContentBuilder
    private func detailToolbar(item: GalleryItem, slot: ImageSlot) -> some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                library.stepImage(-1)
            } label: {
                Label("上一张", systemImage: "chevron.left")
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command])
            .disabled(library.selectedImageIndex == 0)

            Button {
                library.stepImage(1)
            } label: {
                Label("下一张", systemImage: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command])
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if !saveMessage.isEmpty {
                Text(saveMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

// Legacy overlay-based fullscreen. Superseded by macOS-native `NSWindow.toggleFullScreen`
// driven from `WorkspaceShell`, which collapses the split view to detail-only and lets
// the unified toolbar auto-hide. Kept as an empty stub to preserve external refs.
struct FullscreenImageViewerOverlay: View {
    var body: some View { EmptyView() }
}

struct ZoomableImageCanvas<Placeholder: View>: View {
    let url: URL?
    let resetToken: UUID
    let contentInsets: EdgeInsets
    let localMaxPixelSize: CGFloat?
    @ViewBuilder let placeholder: () -> Placeholder
    let onDisplayed: () -> Void

    @State private var zoomScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero
    @State private var imageSize: CGSize?

    init(
        url: URL?,
        resetToken: UUID,
        contentInsets: EdgeInsets,
        localMaxPixelSize: CGFloat? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        onDisplayed: @escaping () -> Void
    ) {
        self.url = url
        self.resetToken = resetToken
        self.contentInsets = contentInsets
        self.localMaxPixelSize = localMaxPixelSize
        self.placeholder = placeholder
        self.onDisplayed = onDisplayed
    }

    var body: some View {
        GeometryReader { proxy in
            let fitSize = contentSize(in: proxy.size)
            let fitCenter = CGPoint(
                x: contentInsets.leading + fitSize.width / 2,
                y: contentInsets.top + fitSize.height / 2
            )

            ZStack {
                RemoteImageView(
                    url: url,
                    contentMode: .fit,
                    priority: .userInitiated,
                    localMaxPixelSize: localMaxPixelSize,
                    onLoaded: onDisplayed,
                    onImageLoaded: { image in
                        imageSize = image.size
                        panOffset = clampedPanOffset(panOffset, in: fitSize, imageSize: image.size)
                        dragStartOffset = panOffset
                    }
                ) {
                    placeholder()
                }
                .frame(width: fitSize.width, height: fitSize.height)
                .scaleEffect(zoomScale)
                .offset(panOffset)
                .position(fitCenter)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .overlay {
                TrackpadPanView { delta in
                    guard zoomScale > 1 else { return }
                    let proposed = CGSize(
                        width: panOffset.width + delta.width,
                        height: panOffset.height + delta.height
                    )
                    panOffset = clampedPanOffset(proposed, in: fitSize, imageSize: imageSize)
                    dragStartOffset = panOffset
                } onMagnify: { magnification, location in
                    zoom(by: magnification, around: locationInContent(location, containerSize: proxy.size), in: fitSize)
                } onMagnifyEnded: {
                    settleZoom(in: fitSize)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let proposed = CGSize(
                            width: dragStartOffset.width + value.translation.width,
                            height: dragStartOffset.height + value.translation.height
                        )
                        panOffset = clampedPanOffset(proposed, in: fitSize, imageSize: imageSize)
                    }
                    .onEnded { _ in
                        panOffset = clampedPanOffset(panOffset, in: fitSize, imageSize: imageSize)
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
        panOffset = .zero
        dragStartOffset = .zero
        imageSize = nil
    }

    private func contentSize(in containerSize: CGSize) -> CGSize {
        CGSize(
            width: max(containerSize.width - contentInsets.leading - contentInsets.trailing, 1),
            height: max(containerSize.height - contentInsets.top - contentInsets.bottom, 1)
        )
    }

    private func locationInContent(_ location: CGPoint, containerSize: CGSize) -> CGPoint {
        CGPoint(
            x: location.x - contentInsets.leading,
            y: location.y - contentInsets.top
        )
    }

    private func zoom(by magnification: CGFloat, around location: CGPoint, in containerSize: CGSize) {
        let currentScale = zoomScale
        let nextScale = min(max(currentScale * (1 + magnification), 0.65), 5)
        guard nextScale != currentScale else { return }

        let center = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        let relativePoint = CGSize(
            width: location.x - center.x,
            height: location.y - center.y
        )
        let scaleRatio = nextScale / currentScale
        let proposedOffset = CGSize(
            width: relativePoint.width * (1 - scaleRatio) + panOffset.width * scaleRatio,
            height: relativePoint.height * (1 - scaleRatio) + panOffset.height * scaleRatio
        )

        zoomScale = nextScale
        panOffset = clampedPanOffset(proposedOffset, in: containerSize, imageSize: imageSize)
        dragStartOffset = panOffset
    }

    private func settleZoom(in containerSize: CGSize) {
        guard zoomScale < 1 else {
            panOffset = clampedPanOffset(panOffset, in: containerSize, imageSize: imageSize)
            dragStartOffset = panOffset
            return
        }

        withAnimation(.snappy(duration: 0.2)) {
            zoomScale = 1
            panOffset = .zero
        }
        dragStartOffset = .zero
    }

    private func clampedPanOffset(_ offset: CGSize, in containerSize: CGSize, imageSize: CGSize?) -> CGSize {
        guard zoomScale > 1 else { return .zero }
        let fittedSize = fittedImageSize(in: containerSize, imageSize: imageSize)
        let maxX = max((fittedSize.width * zoomScale - containerSize.width) / 2, 0)
        let maxY = max((fittedSize.height * zoomScale - containerSize.height) / 2, 0)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    private func fittedImageSize(in containerSize: CGSize, imageSize: CGSize?) -> CGSize {
        guard let imageSize,
              imageSize.width > 0,
              imageSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return containerSize
        }

        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}

private struct TrackpadPanView: NSViewRepresentable {
    let onPan: (CGSize) -> Void
    let onMagnify: (CGFloat, CGPoint) -> Void
    let onMagnifyEnded: () -> Void

    func makeNSView(context: Context) -> NSView {
        ScrollCatcherView(onPan: onPan, onMagnify: onMagnify, onMagnifyEnded: onMagnifyEnded)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let catcher = nsView as? ScrollCatcherView else { return }
        catcher.onPan = onPan
        catcher.onMagnify = onMagnify
        catcher.onMagnifyEnded = onMagnifyEnded
    }

    private final class ScrollCatcherView: NSView {
        var onPan: (CGSize) -> Void
        var onMagnify: (CGFloat, CGPoint) -> Void
        var onMagnifyEnded: () -> Void

        override var isFlipped: Bool { true }

        init(
            onPan: @escaping (CGSize) -> Void,
            onMagnify: @escaping (CGFloat, CGPoint) -> Void,
            onMagnifyEnded: @escaping () -> Void
        ) {
            self.onPan = onPan
            self.onMagnify = onMagnify
            self.onMagnifyEnded = onMagnifyEnded
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

        override func magnify(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            onMagnify(event.magnification, location)
        }

        override func endGesture(with event: NSEvent) {
            onMagnifyEnded()
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
    @Environment(LibraryStore.self) private var library

    let slots: [ImageSlot]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let onReachedEnd: () -> Void

    @State private var viewportWidth: CGFloat = 0
    @State private var lastBatchStart: Int = -1
    private let tilePitch: CGFloat = 82   // 72 缩略图 + 10 间距

    var body: some View {
        ScrollViewReader { scrollProxy in
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
                        .onAppear {
                            // 当倒数第 4 张及以后任何一张露面，就续接下一页。
                            // 推后到下一轮 runloop 避免在 view update 阶段写 @Published。
                            if index >= slots.count - 4 {
                                DispatchQueue.main.async { onReachedEnd() }
                            }
                        }
                    }

                    if library.prefetchPageURL != nil {
                        LoadingFilmstripTile()
                            .onAppear {
                                DispatchQueue.main.async { onReachedEnd() }
                            }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .frame(height: 112)
            .background(.bar)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { viewportWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, value in viewportWidth = value }
                }
            )
            .onChange(of: selectedIndex) { _, index in
                guard slots.indices.contains(index) else { return }
                // 只在选中的缩略图跨过整批可见窗口时才滚动，让用户能在一屏内连续切换。
                let tilesPerBatch = max(Int((viewportWidth - 28) / tilePitch), 1)
                let batchStart = (index / tilesPerBatch) * tilesPerBatch
                guard batchStart != lastBatchStart else { return }
                lastBatchStart = batchStart
                withAnimation(.snappy(duration: 0.22)) {
                    scrollProxy.scrollTo(batchStart, anchor: .leading)
                }
            }
            .onAppear {
                guard slots.indices.contains(selectedIndex) else { return }
                let tilesPerBatch = max(Int((viewportWidth - 28) / tilePitch), 1)
                lastBatchStart = (selectedIndex / tilesPerBatch) * tilesPerBatch
                scrollProxy.scrollTo(lastBatchStart, anchor: .leading)
            }
        }
    }
}

private struct LoadingFilmstripTile: View {
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

private struct PosterWebImage: View {
    let url: URL?
    let contentMode: ContentMode

    var body: some View {
        RemoteImageView(url: url, contentMode: contentMode, priority: .background) {
            Rectangle()
                .fill(.quaternary)
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }
}

private struct SlotThumbnail: View {
    let slot: ImageSlot

    var body: some View {
        RemoteImageView(url: slot.knownURL, contentMode: .fill, priority: .utility) {
            Rectangle()
                .fill(.quaternary)
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
