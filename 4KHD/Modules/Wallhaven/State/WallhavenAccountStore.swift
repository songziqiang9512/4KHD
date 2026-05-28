import Foundation

@MainActor
@Observable
final class WallhavenAccountStore {
    /// Non-nil when the last UserDefaults write failed.
    var keychainError: String?

    /// True during init so the didSet doesn't re-write to UserDefaults.
    private var isLoading = true

    private static let apiKeyDefaultsKey = "com.songziqiang.4khd.wallhavenAPIKey.v1"

    var apiKey: String? {
        didSet {
            guard apiKey != oldValue else { return }
            guard !isLoading else { return }
            if let key = apiKey, !key.isEmpty {
                UserDefaults.standard.set(key, forKey: Self.apiKeyDefaultsKey)
                keychainError = nil
            } else {
                UserDefaults.standard.removeObject(forKey: Self.apiKeyDefaultsKey)
                keychainError = nil
                if purity != .sfw { purity = .sfw }
            }
        }
    }

    private static let purityDefaultsKey = "com.songziqiang.4khd.wallhavenPurity.v1"

    var purity: WallhavenPurity = .sfw {
        didSet {
            UserDefaults.standard.set(purity.rawValue, forKey: Self.purityDefaultsKey)
        }
    }

    var hasAPIKey: Bool {
        guard let key = apiKey, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return true
    }

    var allowedPurities: [WallhavenPurity] {
        hasAPIKey
            ? [.sfw, .sketchy, .nsfw, .all]
            : [.sfw]
    }

    init() {
        apiKey = UserDefaults.standard.string(forKey: Self.apiKeyDefaultsKey)
        isLoading = false
        purity = WallhavenPurity(rawValue: UserDefaults.standard.string(forKey: Self.purityDefaultsKey) ?? "") ?? .sfw
        if !hasAPIKey && purity != .sfw {
            purity = .sfw
        }
    }
}
