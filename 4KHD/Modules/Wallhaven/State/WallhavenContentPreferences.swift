import Foundation
import Observation

enum WallhavenContentLayout: String {
    case list
    case grid
}

@MainActor
@Observable
final class WallhavenContentPreferences {
    private static let layoutDefaultsKey = "com.songziqiang.4khd.wallhavenContentLayout.v1"
    private static let gridColumnCountDefaultsKey = "com.songziqiang.4khd.wallhavenGridColumnCount.v1"
    static let minimumGridColumnCount = 2
    static let maximumGridColumnCount = 6

    var layout: WallhavenContentLayout {
        didSet {
            UserDefaults.standard.set(layout.rawValue, forKey: Self.layoutDefaultsKey)
        }
    }

    var gridColumnCount: Int {
        didSet {
            UserDefaults.standard.set(gridColumnCount, forKey: Self.gridColumnCountDefaultsKey)
        }
    }

    // Filter prefs persisted in UserDefaults so they survive relaunch.
    var preferredCategory: WallhavenCategory {
        didSet { UserDefaults.standard.set(preferredCategory.rawValue, forKey: "com.songziqiang.4khd.wallhavenCategory.v1") }
    }
    var preferredSorting: WallhavenSorting {
        didSet { UserDefaults.standard.set(preferredSorting.rawValue, forKey: "com.songziqiang.4khd.wallhavenSorting.v1") }
    }
    var preferredResolution: WallhavenResolution {
        didSet { UserDefaults.standard.set(preferredResolution.rawValue, forKey: "com.songziqiang.4khd.wallhavenResolution.v1") }
    }
    var preferredRatio: WallhavenRatio {
        didSet { UserDefaults.standard.set(preferredRatio.rawValue, forKey: "com.songziqiang.4khd.wallhavenRatio.v1") }
    }

    var canIncreaseGridColumns: Bool { gridColumnCount < Self.maximumGridColumnCount }
    var canDecreaseGridColumns: Bool { gridColumnCount > Self.minimumGridColumnCount }

    func adjustGridColumns(delta: Int) {
        let next = min(max(gridColumnCount + delta, Self.minimumGridColumnCount), Self.maximumGridColumnCount)
        guard next != gridColumnCount else { return }
        gridColumnCount = next
    }

    init(defaults: UserDefaults = .standard) {
        layout = WallhavenContentLayout(rawValue: defaults.string(forKey: Self.layoutDefaultsKey) ?? "") ?? .grid
        gridColumnCount = defaults.object(forKey: Self.gridColumnCountDefaultsKey) as? Int ?? 4
        preferredCategory = WallhavenCategory(rawValue: defaults.string(forKey: "com.songziqiang.4khd.wallhavenCategory.v1") ?? "") ?? .all
        preferredSorting = WallhavenSorting(rawValue: defaults.string(forKey: "com.songziqiang.4khd.wallhavenSorting.v1") ?? "") ?? .toplist
        preferredResolution = WallhavenResolution(rawValue: defaults.string(forKey: "com.songziqiang.4khd.wallhavenResolution.v1") ?? "") ?? .any
        preferredRatio = WallhavenRatio(rawValue: defaults.string(forKey: "com.songziqiang.4khd.wallhavenRatio.v1") ?? "") ?? .any
    }
}
