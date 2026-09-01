import AppKit
import AVFoundation
import AVKit

/// 爱妹子视频使用独立原生窗口，避免播放器生命周期和图片详情切换互相干扰。
@MainActor
final class KnitVideoPlayerWindowController: NSWindowController, NSWindowDelegate {
    private let contentRoot = NSView()
    private let playerView = AVPlayerView()
    private let loadingIndicator = NSProgressIndicator()
    private var currentSourceURL: URL?
    private var currentPolicySource: OnlineSourcePolicy.Source = .knit
    private var currentSaveAction: (() -> Void)?
    private var playbackProxySessionID: UUID?
    private var playbackGeneration = UUID()
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
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "视频播放"
        window.contentView = contentRoot
        window.contentMinSize = NSSize(width: 560, height: 360)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenAuxiliary]
        playerView.controlsStyle = .floating
        playerView.showsFullScreenToggleButton = true
        playerView.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .large
        loadingIndicator.isDisplayedWhenStopped = false
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentRoot.addSubview(playerView)
        contentRoot.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: contentRoot.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: contentRoot.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: contentRoot.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: contentRoot.bottomAnchor),
            loadingIndicator.centerXAnchor.constraint(equalTo: contentRoot.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: contentRoot.centerYAnchor),
        ])
        super.init(window: window)
        window.delegate = self

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
        referer: String? = nil,
        onSave: (() -> Void)? = nil
    ) {
        guard OnlineSourcePolicy.allows(url, source: source, resource: .media),
              url.pathExtension.lowercased() == "m3u8"
        else {
            clearPlayback()
            return
        }
        clearPlayback()
        let generation = UUID()
        playbackGeneration = generation
        currentPolicySource = source
        updateCurrentVideoContext(url: url, saveAction: onSave)
        presentWindow(title: title, source: source)
        setLoadingVisible(true)

        if let referer, !referer.isEmpty {
            Task { @MainActor in
                do {
                    let prepared = try await OnlineHLSLocalProxy.shared.preparePlayback(
                        mediaURL: url,
                        source: source,
                        userAgent: userAgent,
                        referer: referer
                    )
                    guard self.playbackGeneration == generation else {
                        OnlineHLSLocalProxy.shared.endSession(prepared.sessionID)
                        return
                    }
                    self.playbackProxySessionID = prepared.sessionID
                    self.startPlaying(assetURL: prepared.url, userAgent: userAgent)
                } catch {
                    guard self.playbackGeneration == generation else { return }
                    self.setLoadingVisible(false)
                    self.presentPlaybackFailure(message: error.localizedDescription)
                }
            }
            return
        }
        startPlaying(assetURL: url, userAgent: userAgent)
    }

    func beginPreparingPlayback(title: String, source: OnlineSourcePolicy.Source) {
        currentPolicySource = source
        presentWindow(title: title, source: source)
        setLoadingVisible(true)
    }

    func presentResolveFailure(message: String) {
        setLoadingVisible(false)
        if window?.isVisible != true {
            presentWindow(title: Self.defaultTitle(for: currentPolicySource), source: currentPolicySource)
        }
        presentPlaybackFailure(message: message)
    }

    private func presentWindow(title: String, source: OnlineSourcePolicy.Source) {
        window?.title = title.isEmpty ? Self.defaultTitle(for: source) : title
        if window?.isVisible != true {
            window?.center()
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startPlaying(assetURL: URL, userAgent: String) {
        let asset = AVURLAsset(
            url: assetURL,
            options: [AVURLAssetHTTPUserAgentKey: userAgent]
        )
        let playerItem = AVPlayerItem(asset: asset)
        playerView.player = AVPlayer(playerItem: playerItem)
        observeStatus(of: playerItem)
        setLoadingVisible(false)
        playerView.player?.play()
    }

    override func close() {
        clearPlayback()
        super.close()
    }

    func windowWillClose(_: Notification) {
        clearPlayback()
    }

    private func clearPlayback() {
        playbackGeneration = UUID()
        playerItemStatusObservation?.invalidate()
        playerItemStatusObservation = nil
        dismissPlaybackFailureAlert()
        setLoadingVisible(false)
        if let player = playerView.player {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        playerView.player = nil
        if let window, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        if let sessionID = playbackProxySessionID {
            OnlineHLSLocalProxy.shared.endSession(sessionID)
            playbackProxySessionID = nil
        }
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
        presentPlaybackFailure(
            message: playerItem.error?.localizedDescription ?? "影片资源无法加载，请稍后重试。"
        )
    }

    private func presentPlaybackFailure(message: String) {
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

    private func setLoadingVisible(_ visible: Bool) {
        if visible {
            loadingIndicator.isHidden = false
            loadingIndicator.startAnimation(nil)
        } else {
            loadingIndicator.stopAnimation(nil)
            loadingIndicator.isHidden = true
        }
    }

    private static func defaultTitle(for source: OnlineSourcePolicy.Source) -> String {
        switch source {
        case .knit: "爱妹子视频"
        case .mrds: "每日大赛视频"
        case .quanji: "木瓜视频"
        case .porny: "91PORNY 视频"
        case .tangxin: "糖心Vlog"
        case .gallery, .missKon, .wallhaven: "视频播放"
        }
    }
}
