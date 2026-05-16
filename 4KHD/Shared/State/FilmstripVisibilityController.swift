import Foundation
import Observation

@MainActor
@Observable
final class FilmstripVisibilityController {
    private static let defaultsKey = "com.songziqiang.4khd.showsFilmstrip.v1"

    var isPresented: Bool {
        didSet {
            UserDefaults.standard.set(isPresented, forKey: Self.defaultsKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        if defaults.object(forKey: Self.defaultsKey) == nil {
            isPresented = true
        } else {
            isPresented = defaults.bool(forKey: Self.defaultsKey)
        }
    }

    func toggle() {
        isPresented.toggle()
    }
}
