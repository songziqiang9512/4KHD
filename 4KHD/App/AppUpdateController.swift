import AppKit
import Sparkle

/// 统一管理 Sparkle 自动检查和手动检查更新入口。
@MainActor
final class AppUpdateController {
    static let shared = AppUpdateController()

    private let updaterController: SPUStandardUpdaterController

    private init() {
        #if DEBUG
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #else
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
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
        updaterController.checkForUpdates(sender)
        #endif
    }
}
