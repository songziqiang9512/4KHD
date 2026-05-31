import Foundation
import Observation

enum MissKonContentLayout: String {
    case list
    case grid
}

@MainActor
@Observable
final class MissKonContentPreferences {
    private static let layoutDefaultsKey = "com.songziqiang.4khd.misskonContentLayout.v1"
    private static let gridColumnCountDefaultsKey = "com.songziqiang.4khd.misskonGridColumnCount.v1"
    static let minimumGridColumnCount = 2
    static let maximumGridColumnCount = 6

    var layout: MissKonContentLayout {
        didSet {
            UserDefaults.standard.set(layout.rawValue, forKey: Self.layoutDefaultsKey)
        }
    }

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

    func adjustGridColumns(delta: Int) {
        let nextColumnCount = min(max(gridColumnCount + delta, Self.minimumGridColumnCount), Self.maximumGridColumnCount)
        guard nextColumnCount != gridColumnCount else { return }
        gridColumnCount = nextColumnCount
    }

    init(defaults: UserDefaults = .standard) {
        layout = MissKonContentLayout(rawValue: defaults.string(forKey: Self.layoutDefaultsKey) ?? "") ?? .grid
        gridColumnCount = defaults.object(forKey: Self.gridColumnCountDefaultsKey) as? Int ?? 4
    }
}
