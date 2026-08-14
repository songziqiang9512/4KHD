import Foundation
import Observation

/// 统一收藏模块的状态:对 FavoritesStore 的记录按来源筛选,
/// 并维护当前选中记录。记录顺序保持 FavoritesStore 原始顺序。
/// visibleRecords 为计算属性,直接派生自 favoritesStore.favorites,
/// 收藏变化经 @Observable 观察链自动传导,无需 onFavoritesChanged。
@MainActor
@Observable
final class FavoritesModuleStore {
    let favoritesStore: FavoritesStore

    var filter: FavoriteSourceFilter = .all
    var selectedRecordID: FavoriteRecord.ID?
    var searchText = ""
    private(set) var activeSearchQuery: String?

    var visibleRecords: [FavoriteRecord] {
        let source = filter.source
        let query = activeSearchQuery
        return favoritesStore.favorites.filter { record in
            guard let recordSource = FavoriteSource.source(for: record) else { return false }
            guard source == nil || recordSource == source else { return false }
            guard let query, !query.isEmpty else { return true }
            return record.title.localizedCaseInsensitiveContains(query)
                || record.rawTitle.localizedCaseInsensitiveContains(query)
                || record.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedRecord: FavoriteRecord? {
        guard let selectedRecordID else { return nil }
        return visibleRecords.first { $0.id == selectedRecordID }
    }

    init(favoritesStore: FavoritesStore) {
        self.favoritesStore = favoritesStore
    }

    func select(record: FavoriteRecord?) {
        selectedRecordID = record?.id
    }

    func submitSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearSearch()
            return
        }
        activeSearchQuery = query
        reselectFirstVisibleRecordIfNeeded()
    }

    func clearSearch() {
        searchText = ""
        activeSearchQuery = nil
        reselectFirstVisibleRecordIfNeeded()
    }

    private func reselectFirstVisibleRecordIfNeeded() {
        if let selectedRecordID, visibleRecords.contains(where: { $0.id == selectedRecordID }) {
            return
        }
        selectedRecordID = visibleRecords.first?.id
    }

    /// 单元素调用 bridge 把记录重建为模块 item,供「保存整个图集」等入口复用。
    func galleryItem(for record: FavoriteRecord) -> GalleryItem? {
        GalleryFavoritesBridge.galleryItems(from: [record]).first
    }

    func missKonItem(for record: FavoriteRecord) -> MissKonItem? {
        MissKonFavoritesBridge.missKonItems(from: [record]).first
    }
}
