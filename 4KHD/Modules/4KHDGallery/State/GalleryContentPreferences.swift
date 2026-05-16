import Foundation
import Observation

enum GalleryContentLayout: String {
    case list
    case grid
}

@MainActor
@Observable
final class GalleryContentPreferences {
    private static let defaultsKey = "com.songziqiang.4khd.contentLayout.v1"

    var layout: GalleryContentLayout {
        didSet {
            UserDefaults.standard.set(layout.rawValue, forKey: Self.defaultsKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        let stored = defaults.string(forKey: Self.defaultsKey)
        layout = GalleryContentLayout(rawValue: stored ?? "") ?? .list
    }
}
