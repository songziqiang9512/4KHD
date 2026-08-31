import AppKit
import AVFoundation
import AVKit

/// 爱妹子视频使用独立原生窗口，避免播放器生命周期和图片详情切换互相干扰。
@MainActor
final class KnitVideoPlayerWindowController: NSWindowController, NSWindowDelegate {
    private let playerView = AVPlayerView()
    private var currentSourceURL: URL?
    private var currentPolicySource: OnlineSourcePolicy.Source = .knit
    private var currentSaveAction: (() -> Void)?
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var playbackFailureAlert: NSAlert?
    private lazy var saveVideoMenuItem: NSMenuItem = {
        let item = NSMenuItem(
            title: "保存视频为 MP4…",
            action: #selector(saveVideo(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.image = NSImage(systemSymbolName: "video.badge.arrow.down", accessibilityDescription: nil)
        item.isEnabled = false
        return item
    }()

    private lazy var copySourceURLMenuItem: NSMenuItem = {
        let item = NSMenuItem(
            title: "拷贝影片源 URL",
            action: #selector(copySourceURL(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        item.isEnabled = false
        return item
    }()

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "视频播放"
        panel.contentView = playerView
        panel.contentMinSize = NSSize(width: 560, height: 360)
        panel.isReleasedWhenClosed = false
        panel.tabbingMode = .disallowed
        panel.collectionBehavior = [.fullScreenAuxiliary]
        playerView.controlsStyle = .floating
        playerView.showsFullScreenToggleButton = true
        super.init(window: panel)
        panel.delegate = self

        let contextMenu = NSMenu()
        contextMenu.autoenablesItems = false
        contextMenu.addItem(saveVideoMenuItem)
        contextMenu.addItem(.separator())
        contextMenu.addItem(copySourceURLMenuItem)
        playerView.menu = contextMenu
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func play(
        url: URL,
        title: String,
        source: OnlineSourcePolicy.Source = .knit,
        userAgent: String = KnitRequestFactory.userAgent,
        onSave: (() -> Void)? = nil
    ) {
        guard OnlineSourcePolicy.allows(url, source: source, resource: .media),
              url.pathExtension.lowercased() == "m3u8"
        else {
            clearPlayback()
            return
        }
        clearPlayback()
        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetHTTPUserAgentKey: userAgent]
        )
        let playerItem = AVPlayerItem(asset: asset)
        playerView.player = AVPlayer(playerItem: playerItem)
        observeStatus(of: playerItem)
        currentPolicySource = source
        updateCurrentVideoContext(url: url, saveAction: onSave)
        window?.title = title.isEmpty ? Self.defaultTitle(for: source) : title
        if window?.isVisible != true {
            window?.center()
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        playerView.player?.play()
    }

    func windowWillClose(_: Notification) {
        clearPlayback()
    }

    private func clearPlayback() {
        playerItemStatusObservation?.invalidate()
        playerItemStatusObservation = nil
        dismissPlaybackFailureAlert()
        playerView.player?.pause()
        playerView.player = nil
        currentPolicySource = .knit
        updateCurrentVideoContext(url: nil, saveAction: nil)
    }

    private func observeStatus(of playerItem: AVPlayerItem) {
        playerItemStatusObservation?.invalidate()
        playerItemStatusObservation = playerItem.observe(\.status, options: [.initial, .new]) {
            [weak self, weak playerItem] _, _ in
            guard let playerItem else { return }
            Task { @MainActor [weak self] in
                self?.handleStatusChange(for: playerItem)
            }
        }
    }

    private func handleStatusChange(for playerItem: AVPlayerItem) {
        guard playerView.player?.currentItem === playerItem,
              playerItem.status == .failed else { return }

        // A failed item will not recover by itself. Stop observing immediately so
        // repeated KVO notifications cannot stack duplicate warning sheets.
        playerItemStatusObservation?.invalidate()
        playerItemStatusObservation = nil
        playerView.player?.pause()

        let message = playerItem.error?.localizedDescription ?? "影片资源无法加载，请稍后重试。"
        let alert = makeAppAlert(
            title: "视频播放失败",
            message: message,
            style: .warning
        )
        guard let window, window.isVisible else { return }
        playbackFailureAlert = alert
        alert.applyAppDialogStyle()
        alert.beginSheetModal(for: window) { [weak self, weak alert] _ in
            guard let self, self.playbackFailureAlert === alert else { return }
            self.playbackFailureAlert = nil
        }
    }

    private func dismissPlaybackFailureAlert() {
        guard let alert = playbackFailureAlert else { return }
        playbackFailureAlert = nil
        if let parent = alert.window.sheetParent {
            parent.endSheet(alert.window, returnCode: .cancel)
        }
    }

    private func updateCurrentVideoContext(url: URL?, saveAction: (() -> Void)?) {
        currentSourceURL = url
        currentSaveAction = saveAction
        saveVideoMenuItem.isEnabled = url != nil && saveAction != nil
        copySourceURLMenuItem.isEnabled = url != nil
    }

    @objc private func saveVideo(_: NSMenuItem) {
        guard let url = currentSourceURL,
              OnlineSourcePolicy.allows(url, source: currentPolicySource, resource: .media),
              url.pathExtension.lowercased() == "m3u8",
              let currentSaveAction
        else {
            updateCurrentVideoContext(url: nil, saveAction: nil)
            return
        }
        currentSaveAction()
    }

    @objc private func copySourceURL(_: NSMenuItem) {
        guard let url = currentSourceURL,
              OnlineSourcePolicy.allows(url, source: currentPolicySource, resource: .media),
              url.pathExtension.lowercased() == "m3u8"
        else {
            updateCurrentVideoContext(url: nil, saveAction: nil)
            return
        }
        WorkspaceCurrentReference.web(url).writeToPasteboard()
    }

    private static func defaultTitle(for source: OnlineSourcePolicy.Source) -> String {
        switch source {
        case .knit: "爱妹子视频"
        case .mrds: "每日大赛视频"
        case .gallery, .missKon, .wallhaven: "视频播放"
        }
    }
}
