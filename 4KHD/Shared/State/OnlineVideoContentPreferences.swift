import Foundation
import Observation

@MainActor
@Observable
final class OnlineVideoContentPreferences {
    static let minimumGridColumnCount = 2
    static let maximumGridColumnCount = 6

    private let layoutKey: String
    private let gridColumnsKey: String

    var layout: OnlineVideoContentLayout {
        didSet { UserDefaults.standard.set(layout.rawValue, forKey: layoutKey) }
    }

    var gridColumnCount: Int {
        didSet { UserDefaults.standard.set(gridColumnCount, forKey: gridColumnsKey) }
    }

    var canIncreaseGridColumns: Bool {
        gridColumnCount < Self.maximumGridColumnCount
    }

    var canDecreaseGridColumns: Bool {
        gridColumnCount > Self.minimumGridColumnCount
    }

    init(layoutKey: String, gridColumnsKey: String, defaults: UserDefaults = .standard) {
        self.layoutKey = layoutKey
        self.gridColumnsKey = gridColumnsKey
        layout = OnlineVideoContentLayout(rawValue: defaults.string(forKey: layoutKey) ?? "") ?? .grid
        let storedColumns = defaults.integer(forKey: gridColumnsKey)
        gridColumnCount = storedColumns >= Self.minimumGridColumnCount ? storedColumns : 4
    }

    func adjustGridColumns(delta: Int) {
        gridColumnCount = min(
            max(gridColumnCount + delta, Self.minimumGridColumnCount),
            Self.maximumGridColumnCount
        )
    }
}
