import AppKit
import Sparkle

/// 统一管理 Sparkle 自动检查和手动检查更新入口。
@MainActor
final class AppUpdateController {
    static let shared = AppUpdateController()

    private let updaterController: SPUStandardUpdaterController
    private let isUpdaterConfigured: Bool

    private init() {
        #if DEBUG
        isUpdaterConfigured = false
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #else
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        isUpdaterConfigured = Self.isValidSparklePublicKey(publicKey)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: isUpdaterConfigured,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #endif
    }

    @objc func checkForUpdates(_ sender: Any?) {
        #if DEBUG
        let alert = makeAppAlert(
            title: "调试构建不执行自动更新",
            message: "自动更新只在 GitHub 发布的签名版本中启用。",
            buttons: ["好"]
        )
        presentAppAlert(alert, in: appModalHostWindow())
        #else
        guard isUpdaterConfigured else {
            let alert = makeAppAlert(
                title: "自动更新尚未配置",
                message: "此构建缺少有效的 Sparkle 公钥，请从官方发布页重新下载安装。",
                buttons: ["好"]
            )
            presentAppAlert(alert, in: appModalHostWindow())
            return
        }
        updaterController.checkForUpdates(sender)
        #endif
    }

    private static func isValidSparklePublicKey(_ value: String?) -> Bool {
        guard let value,
              !value.isEmpty,
              !value.contains("$("),
              let decoded = Data(base64Encoded: value),
              decoded.count == 32 else {
            return false
        }
        return true
    }
}
