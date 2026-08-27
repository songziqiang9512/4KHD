import AppKit
import Foundation
import Nuke
import Observation
import UniformTypeIdentifiers

/// 收藏详情的交互状态:缩放重置令牌 + 当前图片保存(按来源配置请求头)。
@MainActor
@Observable
final class FavoritesDetailInteractionController {
    var resetToken = UUID()
    var saveMessage = ""

    @ObservationIgnored private var saveTask: ImageTask?

    deinit {
        saveTask?.cancel()
    }

    func resetZoom() {
        resetToken = UUID()
    }

    func save(imageURL: URL, filename: String, source: FavoriteSource?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.image]
        panel.nameFieldStringValue = filename
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let target = panel.url else { return }

        saveMessage = "保存中"
        saveTask?.cancel()
        let request = RemoteImagePipeline.shared.request(
            for: imageURL,
            priority: .veryHigh,
            configureURLRequest: source?.imageRequestConfigurator ?? { _ in }
        )
        saveTask = RemoteImagePipeline.shared.loadData(with: request) { [weak self] data in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let data else {
                    self.saveMessage = "保存失败"
                    return
                }
                do {
                    try data.write(to: target, options: .atomic)
                    self.saveMessage = "已保存"
                } catch {
                    self.saveMessage = "保存失败"
                }
            }
        }
    }

    func setAsDesktopWallpaper(imageURL: URL, filename: String, source: FavoriteSource?) {
        saveMessage = "下载中"
        saveTask?.cancel()
        let request = RemoteImagePipeline.shared.request(
            for: imageURL,
            priority: .veryHigh,
            configureURLRequest: source?.imageRequestConfigurator ?? { _ in }
        )
        saveTask = RemoteImagePipeline.shared.loadData(with: request) { [weak self] data in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let data else {
                    self.saveMessage = "下载失败"
                    return
                }
                let tempDirectory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("4KHD-Wallpaper", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(
                        at: tempDirectory,
                        withIntermediateDirectories: true
                    )
                    let tempFile = tempDirectory.appendingPathComponent(filename)
                    try data.write(to: tempFile, options: .atomic)
                    LocalDesktopWallpaperSetter.setDesktopWallpaper(tempFile)
                    self.saveMessage = "已设为桌面壁纸"
                } catch {
                    self.saveMessage = "下载失败"
                }
            }
        }
    }
}
