import Foundation

@MainActor
@Observable
final class WallhavenAccountStore {
    /// Non-nil when the last Keychain write failed.
    var keychainError: String?

    var apiKey: String? {
        didSet {
            guard apiKey != oldValue else { return }
            if let key = apiKey, !key.isEmpty {
                if WallhavenKeychain.save(apiKey: key) {
                    keychainError = nil
                } else {
                    // Rollback — keep the old key (may be nil) so purity gating stays correct.
                    apiKey = oldValue
                    keychainError = "无法将 API Key 保存到 Keychain，API Key 未启用"
                    return
                }
            } else {
                WallhavenKeychain.delete()
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

    /// Purity values the user is allowed to select.
    var allowedPurities: [WallhavenPurity] {
        hasAPIKey
            ? [.sfw, .sketchy, .nsfw, .all]
            : [.sfw]
    }

    init() {
        apiKey = WallhavenKeychain.load()
        purity = WallhavenPurity(rawValue: UserDefaults.standard.string(forKey: Self.purityDefaultsKey) ?? "") ?? .sfw
        if !hasAPIKey && purity != .sfw {
            purity = .sfw
        }
    }
}
