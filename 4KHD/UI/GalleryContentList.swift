import AppKit
import SwiftUI

/// 三段式中部内容栏：当前 section 的图集列表（线上 / 收藏）+ 搜索 + 加载更多。
/// 收藏 section 下额外按作者启发式聚合分组。
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
                // 避免在 view update 周期内直接写 store（会触发 publishing-in-update 警告）
                DispatchQueue.main.async {
                    library.select(item)
                }
            }
        )
    }

    var body: some View {
        // shadow 一份 @Bindable 给 .searchable(text:) 用 $library.searchText
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

    // MARK: - 收藏分组

    private var shouldGroupFavorites: Bool {
        library.section == .favorites && library.activeSearchQuery == nil
    }

    private var favoriteAuthorGroups: [FavoriteAuthorGroup] {
        groupedFavoriteItems()
            .map { author, items in
                FavoriteAuthorGroup(
                    author: author,
                    items: items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                )
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
