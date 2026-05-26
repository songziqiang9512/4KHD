import AppKit
import Foundation
import Nuke
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class WallhavenDetailInteractionController {
    var resetToken = UUID()
    var saveMessage = ""

    @ObservationIgnored private var saveTask: ImageTask?

    deinit {
        saveTask?.cancel()
    }

    func resetZoom() {
        resetToken = UUID()
    }

    func save(imageURL: URL, filename: String) {
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
            configureURLRequest: WallhavenRequestFactory.configureImageRequest
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

    func saveWallpaper(_ wallpaper: Wallpaper) {
        guard let fullImageUrl = wallpaper.fullImageUrl else {
            saveMessage = "无法获取下载地址，请等待详情加载完成后重试"
            return
        }
        let filename = "wallhaven-\(wallpaper.id).\(wallpaper.fileExtensionForSave)"
        save(imageURL: fullImageUrl, filename: filename)
    }

    func setAsDesktopWallpaper(_ wallpaper: Wallpaper, retryAfterResolve: @escaping (@escaping (Wallpaper) -> Void) -> Void) {
        guard let fullImageUrl = wallpaper.fullImageUrl else {
            saveMessage = "正在获取原图地址..."
            retryAfterResolve { [weak self] resolved in
                self?.setAsDesktopWallpaper(resolved, retryAfterResolve: { _ in })
            }
            return
        }
        saveMessage = "下载中"
        saveTask?.cancel()
        let request = RemoteImagePipeline.shared.request(
            for: fullImageUrl,
            priority: .veryHigh,
            configureURLRequest: WallhavenRequestFactory.configureImageRequest
        )
        saveTask = RemoteImagePipeline.shared.loadData(with: request) { [weak self] data in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let data else {
                    self.saveMessage = "下载失败"
                    return
                }
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("4KHD-Wallpaper", isDirectory: true)
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let ext = wallpaper.fileExtensionForSave
                let tempFile = tempDir.appendingPathComponent("wallhaven-\(wallpaper.id).\(ext)")
                do {
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
