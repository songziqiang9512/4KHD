import Foundation
import Observation

enum LocalContentLayout: String {
    case list
    case grid
}

enum LocalImageSortField: String, CaseIterable, Identifiable {
    case name
    case modifiedDate
    case fileSize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "文件名"
        case .modifiedDate: "修改时间"
        case .fileSize: "文件大小"
        }
    }
}

enum LocalImageSortDirection: String, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ascending: "正序"
        case .descending: "逆序"
        }
    }
}

@MainActor
@Observable
final class LocalLibraryContentPreferences {
    private static let layoutDefaultsKey = "com.songziqiang.4khd.localContentLayout.v1"
    private static let sortFieldDefaultsKey = "com.songziqiang.4khd.localImageSortField.v1"
    private static let sortDirectionDefaultsKey = "com.songziqiang.4khd.localImageSortDirection.v1"
    private static let gridColumnCountDefaultsKey = "com.songziqiang.4khd.localGridColumnCount.v1"
    private static let legacyGridColumnOffsetDefaultsKey = "com.songziqiang.4khd.localGridColumnOffset.v1"
    static let minimumGridColumnCount = 2
    static let maximumGridColumnCount = 6

    var layout: LocalContentLayout {
        didSet {
            UserDefaults.standard.set(layout.rawValue, forKey: Self.layoutDefaultsKey)
        }
    }

    var sortField: LocalImageSortField {
        didSet {
            UserDefaults.standard.set(sortField.rawValue, forKey: Self.sortFieldDefaultsKey)
        }
    }

    var sortDirection: LocalImageSortDirection {
        didSet {
            UserDefaults.standard.set(sortDirection.rawValue, forKey: Self.sortDirectionDefaultsKey)
        }
    }

    var searchText = ""

    var gridColumnCount: Int {
        didSet {
            UserDefaults.standard.set(gridColumnCount, forKey: Self.gridColumnCountDefaultsKey)
        }
    }

    var canIncreaseGridColumns: Bool {
        gridColumnCount < Self.maximumGridColumnCount
    }

    var canDecreaseGridColumns: Bool {
        gridColumnCount > Self.minimumGridColumnCount
    }

    init(defaults: UserDefaults = .standard) {
        let storedLayout = defaults.string(forKey: Self.layoutDefaultsKey)
        let storedSortField = defaults.string(forKey: Self.sortFieldDefaultsKey)
        let storedSortDirection = defaults.string(forKey: Self.sortDirectionDefaultsKey)
        layout = LocalContentLayout(rawValue: storedLayout ?? "") ?? .grid
        sortField = LocalImageSortField(rawValue: storedSortField ?? "") ?? .name
        sortDirection = LocalImageSortDirection(rawValue: storedSortDirection ?? "") ?? .ascending
        if let storedGridColumnCount = defaults.object(forKey: Self.gridColumnCountDefaultsKey) as? Int {
            gridColumnCount = Self.clampedGridColumnCount(storedGridColumnCount)
        } else {
            let legacyOffset = defaults.integer(forKey: Self.legacyGridColumnOffsetDefaultsKey)
            gridColumnCount = Self.clampedGridColumnCount(Self.minimumGridColumnCount + legacyOffset)
        }
    }

    func adjustGridColumns(delta: Int) {
        let nextColumnCount = Self.clampedGridColumnCount(gridColumnCount + delta)
        guard nextColumnCount != gridColumnCount else { return }
        gridColumnCount = nextColumnCount
    }

    func gridColumnLimits() -> (minimum: Int, maximum: Int) {
        (Self.minimumGridColumnCount, gridColumnCount)
    }

    private static func clampedGridColumnCount(_ count: Int) -> Int {
        min(max(count, minimumGridColumnCount), maximumGridColumnCount)
    }
}
