import Foundation
import Observation

/// 统一收藏模块的状态:对 FavoritesStore 的记录按来源筛选,
/// 并维护当前选中记录。记录顺序保持 FavoritesStore 原始顺序。
/// visibleRecords 为计算属性,直接派生自 favoritesStore.favorites,
/// 收藏变化经 @Observable 观察链自动传导,无需额外回调链。
@MainActor
@Observable
final class FavoritesModuleStore {
    let favoritesStore: FavoritesStore

    var filter: FavoriteSourceFilter = .all
    var selectedRecordID: FavoriteRecord.ID?
    var searchText = ""
    private(set) var activeSearchQuery: String?

    /// visibleRecords 缓存键:filter/查询词/收藏修订号任一变化即重算。
    private struct VisibleRecordsKey: Equatable {
        let filter: FavoriteSourceFilter
        let query: String?
        let revision: Int
    }

    @ObservationIgnored private var cachedVisibleRecords: [FavoriteRecord] = []
    @ObservationIgnored private var cachedVisibleRecordsKey: VisibleRecordsKey?

    var visibleRecords: [FavoriteRecord] {
        // 读取 filter/activeSearchQuery/favoritesRevision 保持 @Observable 依赖注册,
        // favorites 变化经 revision 自增传导。
        let key = VisibleRecordsKey(
            filter: filter,
            query: activeSearchQuery,
            revision: favoritesStore.favoritesRevision
        )
        if let cachedKey = cachedVisibleRecordsKey, cachedKey == key {
            return cachedVisibleRecords
        }
        let source = filter.source
        let query = activeSearchQuery
        let records = favoritesStore.favorites.filter { record in
            guard let recordSource = FavoriteSource.source(for: record) else { return false }
            guard source == nil || recordSource == source else { return false }
            guard let query, !query.isEmpty else { return true }
            return record.title.localizedCaseInsensitiveContains(query)
                || record.rawTitle.localizedCaseInsensitiveContains(query)
                || record.subtitle.localizedCaseInsensitiveContains(query)
        }
        cachedVisibleRecords = records
        cachedVisibleRecordsKey = key
        return records
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

}
