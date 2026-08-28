import Foundation
import Observation

/// 统一收藏模块的状态:对 FavoritesStore 的记录按来源筛选,
/// 并维护当前选中记录。记录顺序保持 FavoritesStore 原始顺序。
/// visibleRecords 为计算属性,直接派生自 favoritesStore.favorites,
/// 收藏变化经 @Observable 观察链自动传导,无需额外回调链。
@MainActor
@Observable
final class FavoritesModuleStore {
    typealias SelectionIdentity = String

    let favoritesStore: FavoritesStore

    private(set) var filter: FavoriteSourceFilter = .all
    private(set) var selectedRecordIdentity: SelectionIdentity?
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
        guard let selectedRecordIdentity else { return nil }
        return visibleRecords.first {
            selectionIdentity(for: $0) == selectedRecordIdentity
        }
    }

    /// 兼容工具栏与 Inspector 的只读 raw id；选择真值使用包含来源的详情 URL 身份。
    var selectedRecordID: FavoriteRecord.ID? {
        selectedRecord?.id
    }

    init(favoritesStore: FavoritesStore) {
        self.favoritesStore = favoritesStore
        observeFavoritesRevision()
    }

    func select(record: FavoriteRecord?) {
        selectedRecordIdentity = record.map { selectionIdentity(for: $0) }
    }

    nonisolated static func selectionIdentity(for record: FavoriteRecord) -> SelectionIdentity {
        let detailURL = record.detailURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detailURL.isEmpty { return detailURL }
        return "\(record.sourceID)\u{1F}\(record.id)"
    }

    nonisolated func selectionIdentity(for record: FavoriteRecord) -> SelectionIdentity {
        Self.selectionIdentity(for: record)
    }

    func setFilter(_ filter: FavoriteSourceFilter) {
        self.filter = filter
        reconcileSelection()
    }

    /// 收藏删除、筛选或搜索变化后同步选择；空结果必须清掉旧选择。
    func reconcileSelection() {
        if let selectedRecordIdentity,
           visibleRecords.contains(where: {
               selectionIdentity(for: $0) == selectedRecordIdentity
           }) {
            return
        }
        selectedRecordIdentity = visibleRecords.first.map { selectionIdentity(for: $0) }
    }

    private func observeFavoritesRevision() {
        withObservationTracking {
            _ = favoritesStore.favoritesRevision
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reconcileSelection()
                self.observeFavoritesRevision()
            }
        }
    }

    func canStepSourceRecord(from record: FavoriteRecord, delta: Int) -> Bool {
        adjacentSourceRecord(from: record, delta: delta) != nil
    }

    @discardableResult
    func stepSourceRecord(from record: FavoriteRecord, delta: Int) -> Bool {
        guard let next = adjacentSourceRecord(from: record, delta: delta) else { return false }
        select(record: next)
        return true
    }

    private func adjacentSourceRecord(from record: FavoriteRecord, delta: Int) -> FavoriteRecord? {
        guard delta != 0, let source = FavoriteSource.source(for: record) else { return nil }
        let sourceRecords = visibleRecords.filter { FavoriteSource.source(for: $0) == source }
        guard let current = sourceRecords.firstIndex(of: record) else { return nil }
        let next = current + delta
        guard sourceRecords.indices.contains(next) else { return nil }
        return sourceRecords[next]
    }

    func submitSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearSearch()
            return
        }
        activeSearchQuery = query
        reconcileSelection()
    }

    func clearSearch() {
        searchText = ""
        activeSearchQuery = nil
        reconcileSelection()
    }

}
