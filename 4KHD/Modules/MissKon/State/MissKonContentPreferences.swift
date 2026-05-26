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

    var layout: MissKonContentLayout {
        didSet {
            UserDefaults.standard.set(layout.rawValue, forKey: Self.layoutDefaultsKey)
        }
    }

    var searchText = ""

    init(defaults: UserDefaults = .standard) {
        layout = MissKonContentLayout(rawValue: defaults.string(forKey: Self.layoutDefaultsKey) ?? "") ?? .grid
    }
}
