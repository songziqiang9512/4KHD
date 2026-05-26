import Foundation
import Observation

enum GalleryContentLayout: String {
    case list
    case grid
}

@MainActor
@Observable
final class GalleryContentPreferences {
    private static let layoutKey = "com.songziqiang.4khd.contentLayout.v1"
    private static let gridColumnsKey = "com.songziqiang.4khd.gridColumnCount.v1"

    static let minimumGridColumnCount = 2
    static let maximumGridColumnCount = 6

    var layout: GalleryContentLayout {
        didSet {
            UserDefaults.standard.set(layout.rawValue, forKey: Self.layoutKey)
        }
    }

    var gridColumnCount: Int {
        didSet {
            UserDefaults.standard.set(gridColumnCount, forKey: Self.gridColumnsKey)
        }
    }

    var canIncreaseGridColumns: Bool { gridColumnCount < Self.maximumGridColumnCount }
    var canDecreaseGridColumns: Bool { gridColumnCount > Self.minimumGridColumnCount }

    func adjustGridColumns(delta: Int) {
        gridColumnCount = min(max(gridColumnCount + delta, Self.minimumGridColumnCount), Self.maximumGridColumnCount)
    }

    init(defaults: UserDefaults = .standard) {
        let stored = defaults.string(forKey: Self.layoutKey)
        layout = GalleryContentLayout(rawValue: stored ?? "") ?? .list
        let storedColumns = defaults.integer(forKey: Self.gridColumnsKey)
        gridColumnCount = storedColumns >= Self.minimumGridColumnCount ? storedColumns : 4
    }
}
