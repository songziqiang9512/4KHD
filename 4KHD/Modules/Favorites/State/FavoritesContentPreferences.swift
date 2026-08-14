import Foundation
import Observation

enum FavoritesContentLayout: String {
    case list
    case grid
}

@MainActor
@Observable
final class FavoritesContentPreferences {
    private static let layoutDefaultsKey = "com.songziqiang.4khd.favoritesContentLayout.v1"
    private static let gridColumnCountDefaultsKey = "com.songziqiang.4khd.favoritesGridColumnCount.v1"
    static let minimumGridColumnCount = 2
    static let maximumGridColumnCount = 6

    var layout: FavoritesContentLayout {
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
        layout = FavoritesContentLayout(rawValue: defaults.string(forKey: Self.layoutDefaultsKey) ?? "") ?? .grid
        gridColumnCount = defaults.object(forKey: Self.gridColumnCountDefaultsKey) as? Int ?? 4
    }
}
