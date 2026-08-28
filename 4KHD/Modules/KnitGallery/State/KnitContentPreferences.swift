import Foundation
import Observation

enum KnitContentLayout: String {
    case list
    case grid
}

@MainActor
@Observable
final class KnitContentPreferences {
    private static let layoutKey = "com.songziqiang.4khd.knitContentLayout.v1"
    private static let gridColumnsKey = "com.songziqiang.4khd.knitGridColumnCount.v1"

    static let minimumGridColumnCount = 2
    static let maximumGridColumnCount = 6

    var layout: KnitContentLayout {
        didSet { UserDefaults.standard.set(layout.rawValue, forKey: Self.layoutKey) }
    }

    var gridColumnCount: Int {
        didSet { UserDefaults.standard.set(gridColumnCount, forKey: Self.gridColumnsKey) }
    }

    var canIncreaseGridColumns: Bool { gridColumnCount < Self.maximumGridColumnCount }
    var canDecreaseGridColumns: Bool { gridColumnCount > Self.minimumGridColumnCount }

    init(defaults: UserDefaults = .standard) {
        layout = KnitContentLayout(rawValue: defaults.string(forKey: Self.layoutKey) ?? "") ?? .grid
        let storedColumns = defaults.integer(forKey: Self.gridColumnsKey)
        gridColumnCount = storedColumns >= Self.minimumGridColumnCount ? storedColumns : 4
    }

    func adjustGridColumns(delta: Int) {
        gridColumnCount = min(
            max(gridColumnCount + delta, Self.minimumGridColumnCount),
            Self.maximumGridColumnCount
        )
    }
}
