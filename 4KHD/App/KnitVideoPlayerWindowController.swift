import AppKit
import AVFoundation
import AVKit

/// 爱妹子视频使用独立原生窗口，避免播放器生命周期和图片详情切换互相干扰。
@MainActor
final class KnitVideoPlayerWindowController: NSWindowController, NSWindowDelegate {
    private let contentRoot = KnitVideoPlayerRootView()
    private let playerView = AVPlayerView()
    private let clickCatcher = KnitVideoPlayerClickCatcherView()
    private let controlsView = KnitVideoPlayerControlsView()
    private let loadingIndicator = NSProgressIndicator()
    private var currentSourceURL: URL?
    private var currentPolicySource: OnlineSourcePolicy.Source = .knit
    private var currentSaveAction: (() -> Void)?
    private var playbackProxySessionID: UUID?
    private var playbackGeneration = UUID()
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var playerItemDurationObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var activeSeekID: UUID?
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
        window.contentMinSize = NSSize(width: 720, height: 400)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenAuxiliary]
        playerView.controlsStyle = .none
        playerView.showsFullScreenToggleButton = false
        playerView.translatesAutoresizingMaskIntoConstraints = false
        clickCatcher.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .large
        loadingIndicator.isDisplayedWhenStopped = false
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentRoot.addSubview(playerView)
        contentRoot.addSubview(clickCatcher)
        contentRoot.addSubview(controlsView)
        contentRoot.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: contentRoot.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: contentRoot.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: contentRoot.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: contentRoot.bottomAnchor),
            clickCatcher.leadingAnchor.constraint(equalTo: contentRoot.leadingAnchor),
            clickCatcher.trailingAnchor.constraint(equalTo: contentRoot.trailingAnchor),
            clickCatcher.topAnchor.constraint(equalTo: contentRoot.topAnchor),
            clickCatcher.bottomAnchor.constraint(equalTo: contentRoot.bottomAnchor),
            controlsView.centerXAnchor.constraint(equalTo: contentRoot.centerXAnchor),
            controlsView.bottomAnchor.constraint(equalTo: contentRoot.bottomAnchor, constant: -12),
            controlsView.leadingAnchor.constraint(
                greaterThanOrEqualTo: contentRoot.leadingAnchor,
                constant: 16
            ),
            controlsView.trailingAnchor.constraint(
                lessThanOrEqualTo: contentRoot.trailingAnchor,
                constant: -16
            ),
            loadingIndicator.centerXAnchor.constraint(equalTo: contentRoot.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: contentRoot.centerYAnchor),
        ])
        super.init(window: window)
        window.delegate = self
        contentRoot.onKeyDown = { [weak self] event in
            self?.handlePlaybackKey(event) ?? false
        }
        clickCatcher.onClick = { [weak self] in
            guard let self else { return }
            if self.controlsView.dismissAccessoryPopovers() { return }
            self.toggleControlsVisible()
        }
        controlsView.onTogglePlay = { [weak self] in
            self?.togglePlayPause()
            self?.restoreKeyFocus()
        }
        controlsView.onSkip = { [weak self] delta in
            self?.skip(by: delta)
            self?.restoreKeyFocus()
        }
        controlsView.onSeekFraction = { [weak self] fraction in
            self?.seek(toFraction: fraction)
            self?.restoreKeyFocus()
        }
        controlsView.onVolume = { [weak self] volume in
            self?.applyVolume(volume, persist: true)
        }
        controlsView.onRate = { [weak self] rate in
            self?.applyRate(rate, persist: true)
            self?.restoreKeyFocus()
        }
        controlsView.setPlaybackEnabled(false)
        controlsView.setVolume(WorkspaceVideoPlayerTransport.storedVolume())
        controlsView.setRate(WorkspaceVideoPlayerTransport.storedRate())

        let contextMenu = NSMenu()
        contextMenu.autoenablesItems = false
        contextMenu.addItem(saveVideoMenuItem)
        contextMenu.addItem(.separator())
        contextMenu.addItem(copySourceURLMenuItem)
        playerView.menu = contextMenu
        clickCatcher.menu = contextMenu
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
        setControlsVisible(true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        restoreKeyFocus()
    }

    private func startPlaying(assetURL: URL, userAgent: String) {
        let asset = AVURLAsset(
            url: assetURL,
            options: [AVURLAssetHTTPUserAgentKey: userAgent]
        )
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        player.volume = WorkspaceVideoPlayerTransport.storedVolume()
        player.defaultRate = WorkspaceVideoPlayerTransport.storedRate()
        playerView.player = player
        observeStatus(of: playerItem)
        observeDuration(of: playerItem)
        observeTimeControl(of: player)
        observeTime(of: player)
        controlsView.setPlaybackEnabled(true)
        controlsView.setPlaying(true)
        controlsView.setVolume(player.volume)
        controlsView.setRate(player.defaultRate)
        controlsView.setCurrentTime(0)
        setLoadingVisible(false)
        player.play()
        restoreKeyFocus()
    }

    override func close() {
        clearPlayback()
        super.close()
    }

    func windowWillClose(_: Notification) {
        clearPlayback()
    }

    func windowDidBecomeKey(_: Notification) {
        restoreKeyFocus()
    }

    private func clearPlayback() {
        playbackGeneration = UUID()
        activeSeekID = nil
        controlsView.dismissAccessoryPopovers()
        playerItemStatusObservation?.invalidate()
        playerItemStatusObservation = nil
        playerItemDurationObservation?.invalidate()
        playerItemDurationObservation = nil
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        if let timeObserver, let player = playerView.player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        dismissPlaybackFailureAlert()
        setLoadingVisible(false)
        if let player = playerView.player {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        playerView.player = nil
        controlsView.setPlaybackEnabled(false)
        controlsView.setPlaying(false)
        controlsView.setDuration(nil)
        controlsView.setCurrentTime(0)
        setControlsVisible(true)
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

    private func observeDuration(of playerItem: AVPlayerItem) {
        playerItemDurationObservation?.invalidate()
        playerItemDurationObservation = playerItem.observe(\.duration, options: [.initial, .new]) {
            [weak self, weak playerItem] _, _ in
            guard let playerItem else { return }
            Task { @MainActor [weak self] in
                self?.controlsView.setDuration(WorkspaceVideoPlayerTransport.durationSeconds(from: playerItem))
            }
        }
    }

    private func observeTimeControl(of player: AVPlayer) {
        timeControlObservation?.invalidate()
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) {
            [weak self, weak player] _, _ in
            guard let player else { return }
            Task { @MainActor [weak self] in
                self?.controlsView.setPlaying(player.timeControlStatus == .playing)
            }
        }
    }

    private func observeTime(of player: AVPlayer) {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            Task { @MainActor [weak self] in
                guard let self, self.activeSeekID == nil else { return }
                self.controlsView.setCurrentTime(max(seconds, 0))
            }
        }
    }

    private func handleStatusChange(for playerItem: AVPlayerItem) {
        guard playerView.player?.currentItem === playerItem else { return }
        if playerItem.status == .readyToPlay {
            controlsView.setDuration(WorkspaceVideoPlayerTransport.durationSeconds(from: playerItem))
            return
        }
        guard playerItem.status == .failed else { return }

        // A failed item will not recover by itself. Stop observing immediately so
        // repeated KVO notifications cannot stack duplicate warning sheets.
        playerItemStatusObservation?.invalidate()
        playerItemStatusObservation = nil
        playerView.player?.pause()
        controlsView.setPlaybackEnabled(false)
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

    private func toggleControlsVisible() {
        setControlsVisible(controlsView.isHidden)
        restoreKeyFocus()
    }

    private func setControlsVisible(_ visible: Bool) {
        if !visible {
            controlsView.dismissAccessoryPopovers()
        }
        controlsView.isHidden = !visible
    }

    private func togglePlayPause() {
        guard let player = playerView.player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            applyRate(WorkspaceVideoPlayerTransport.nearestRate(player.defaultRate), persist: false)
            player.play()
        }
    }

    private func skip(by delta: TimeInterval) {
        guard let player = playerView.player else { return }
        let current = player.currentTime().seconds
        guard current.isFinite else { return }
        let duration = player.currentItem.flatMap(WorkspaceVideoPlayerTransport.durationSeconds(from:))
        let target = WorkspaceVideoPlayerTransport.clampedTime(
            current: max(current, 0),
            delta: delta,
            duration: duration
        )
        seek(player: player, to: target)
    }

    private func seek(toFraction fraction: Double) {
        guard let player = playerView.player,
              let duration = player.currentItem.flatMap(WorkspaceVideoPlayerTransport.durationSeconds(from:)),
              duration > 0
        else { return }
        let target = WorkspaceVideoPlayerTransport.clampedTime(
            current: 0,
            delta: min(max(fraction, 0), 1) * duration,
            duration: duration
        )
        seek(player: player, to: target)
    }

    private func seek(player: AVPlayer, to target: TimeInterval) {
        let seekID = UUID()
        activeSeekID = seekID
        controlsView.setCurrentTime(target)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.activeSeekID == seekID else { return }
                self.activeSeekID = nil
                let actual = player.currentTime().seconds
                if actual.isFinite {
                    self.controlsView.setCurrentTime(max(actual, 0))
                }
            }
        }
    }

    private func applyVolume(_ volume: Float, persist: Bool) {
        let clamped = min(max(volume, 0), 1)
        playerView.player?.volume = clamped
        controlsView.setVolume(clamped)
        if persist {
            WorkspaceVideoPlayerTransport.storeVolume(clamped)
        }
    }

    private func applyRate(_ rate: Float, persist: Bool) {
        let resolved = WorkspaceVideoPlayerTransport.nearestRate(rate)
        guard let player = playerView.player else {
            controlsView.setRate(resolved)
            if persist { WorkspaceVideoPlayerTransport.storeRate(resolved) }
            return
        }
        player.defaultRate = resolved
        if player.timeControlStatus == .playing {
            player.rate = resolved
        }
        controlsView.setRate(resolved)
        if persist {
            WorkspaceVideoPlayerTransport.storeRate(resolved)
        }
    }

    private func handlePlaybackKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers.isEmpty else { return false }
        switch event.keyCode {
        case 49:
            togglePlayPause()
            return true
        case 123:
            skip(by: -WorkspaceVideoPlayerTransport.keyboardSkipSeconds)
            return true
        case 124:
            skip(by: WorkspaceVideoPlayerTransport.keyboardSkipSeconds)
            return true
        default:
            return false
        }
    }

    private func restoreKeyFocus() {
        window?.makeFirstResponder(contentRoot)
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
            controlsView.setPlaybackEnabled(false)
        } else {
            loadingIndicator.stopAnimation(nil)
            loadingIndicator.isHidden = true
            controlsView.setPlaybackEnabled(playerView.player != nil)
        }
    }

    private static func defaultTitle(for source: OnlineSourcePolicy.Source) -> String {
        switch source {
        case .knit: "爱妹子视频"
        case .mrds: "每日大赛视频"
        case .quanji: "木瓜视频"
        case .porny: "91PORNY 视频"
        case .tangxin: "糖心Vlog"
        case .taiav: "TaiAV"
        case .gallery, .missKon, .wallhaven: "视频播放"
        }
    }
}

@MainActor
private final class KnitVideoPlayerRootView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }
}

@MainActor
private final class KnitVideoPlayerClickCatcherView: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with _: NSEvent) {
        onClick?()
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }
}
