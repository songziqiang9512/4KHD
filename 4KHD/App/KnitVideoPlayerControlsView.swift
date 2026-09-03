import AppKit

@MainActor
final class KnitVideoPlayerControlsView: NSView {
    var onTogglePlay: (() -> Void)?
    var onSkip: ((TimeInterval) -> Void)?
    var onSeekFraction: ((Double) -> Void)?
    var onVolume: ((Float) -> Void)?
    var onRate: ((Float) -> Void)?

    private let chrome = DetailOverlayChromeView()
    private let currentTimeLabel = KnitVideoPlayerControlsView.makeTimeLabel(alignment: .left)
    private let durationLabel = KnitVideoPlayerControlsView.makeTimeLabel(alignment: .right)
    private let progressSlider = NSSlider()
    private let playPauseButton = NSButton()
    private let volumeButton = NSButton()
    private let speedButton = NSButton()
    private let volumePopover = KnitVideoPlayerSliderPopover.volume()
    private let speedPopover = KnitVideoPlayerSliderPopover.speed()
    private var skipButtons: [NSButton] = []
    private(set) var isScrubbing = false
    private var duration: TimeInterval?
    private var volume: Float = WorkspaceVideoPlayerTransport.defaultVolume
    private var rate: Float = WorkspaceVideoPlayerTransport.defaultRate

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        chrome.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chrome, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: trailingAnchor),
            chrome.topAnchor.constraint(equalTo: topAnchor),
            chrome.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setupProgress()
        setupTransport()
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func setPlaybackEnabled(_ enabled: Bool) {
        playPauseButton.isEnabled = enabled
        volumeButton.isEnabled = enabled
        speedButton.isEnabled = enabled
        for button in skipButtons {
            button.isEnabled = enabled
        }
        if !enabled {
            dismissAccessoryPopovers()
        }
        refreshProgressEnabled()
    }

    @discardableResult
    func dismissAccessoryPopovers() -> Bool {
        let wasShowing = volumePopover.isShown || speedPopover.isShown
        volumePopover.close()
        speedPopover.close()
        return wasShowing
    }

    func setDuration(_ seconds: TimeInterval?) {
        duration = seconds
        durationLabel.stringValue = seconds.map(WorkspaceVideoPlayerTransport.formatClock) ?? "--:--"
        refreshProgressEnabled()
    }

    func setCurrentTime(_ seconds: TimeInterval) {
        guard !isScrubbing else { return }
        currentTimeLabel.stringValue = WorkspaceVideoPlayerTransport.formatClock(seconds)
        if let duration, duration > 0 {
            progressSlider.doubleValue = min(max(seconds / duration, 0), 1)
        } else {
            progressSlider.doubleValue = 0
        }
    }

    func setPlaying(_ playing: Bool) {
        let symbol = playing ? "pause.fill" : "play.fill"
        playPauseButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: playing ? "暂停" : "播放")
        playPauseButton.toolTip = playing ? "暂停" : "播放"
    }

    func setVolume(_ volume: Float) {
        let clamped = min(max(volume, 0), 1)
        self.volume = clamped
        volumeButton.title = "\(Int((clamped * 100).rounded()))%"
        volumePopover.setValue(Double(clamped), label: volumeButton.title)
    }

    func setRate(_ rate: Float) {
        let resolved = WorkspaceVideoPlayerTransport.nearestRate(rate)
        self.rate = resolved
        speedButton.title = WorkspaceVideoPlayerTransport.rateLabel(resolved)
        speedPopover.setValue(
            Double(WorkspaceVideoPlayerTransport.rateIndex(resolved)),
            label: speedButton.title
        )
    }

    private func setupProgress() {
        progressSlider.minValue = 0
        progressSlider.maxValue = 1
        progressSlider.doubleValue = 0
        progressSlider.isContinuous = true
        progressSlider.controlSize = .regular
        progressSlider.target = self
        progressSlider.action = #selector(progressChanged(_:))
        progressSlider.sendAction(on: [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
        progressSlider.translatesAutoresizingMaskIntoConstraints = false
        progressSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        progressSlider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let timeRow = NSStackView(views: [currentTimeLabel, NSView(), durationLabel])
        timeRow.orientation = .horizontal
        timeRow.alignment = .centerY
        timeRow.spacing = 8
        timeRow.translatesAutoresizingMaskIntoConstraints = false

        let progressStack = NSStackView(views: [timeRow, progressSlider])
        progressStack.orientation = .vertical
        progressStack.alignment = .leading
        progressStack.spacing = 2
        progressStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressStack)

        currentTimeLabel.stringValue = "0:00"
        durationLabel.stringValue = "--:--"
        currentTimeLabel.setContentHuggingPriority(.required, for: .horizontal)
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            progressStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            progressStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            progressStack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            timeRow.widthAnchor.constraint(equalTo: progressStack.widthAnchor),
            progressSlider.widthAnchor.constraint(equalTo: progressStack.widthAnchor),
        ])
    }

    private func setupTransport() {
        configureTextButton(playPauseButton, title: "", tooltip: "播放", action: #selector(togglePlay))
        playPauseButton.imagePosition = .imageOnly
        playPauseButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "播放")
        playPauseButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)

        let rewindStack = makeSkipStack(direction: -1)
        let forwardStack = makeSkipStack(direction: 1)

        configureTextButton(volumeButton, title: "100%", tooltip: "音量", action: #selector(toggleVolumePopover))
        configureTextButton(speedButton, title: WorkspaceVideoPlayerTransport.rateLabel(1), tooltip: "倍速", action: #selector(toggleSpeedPopover))
        volumePopover.onChange = { [weak self] value in
            self?.onVolume?(Float(value))
        }
        speedPopover.onChange = { [weak self] value in
            let index = min(max(Int(value.rounded()), 0), WorkspaceVideoPlayerTransport.rates.count - 1)
            self?.onRate?(WorkspaceVideoPlayerTransport.rates[index])
        }

        let bottom = NSStackView(views: [
            rewindStack,
            volumeButton,
            playPauseButton,
            speedButton,
            forwardStack,
        ])
        bottom.orientation = .horizontal
        bottom.alignment = .centerY
        bottom.spacing = 8
        bottom.translatesAutoresizingMaskIntoConstraints = false
        bottom.setHuggingPriority(.required, for: .horizontal)
        bottom.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(bottom)

        let sampleSkip = skipButtons.first { $0.title == "-10s" } ?? skipButtons[0]
        NSLayoutConstraint.activate([
            bottom.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            bottom.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            bottom.topAnchor.constraint(equalTo: topAnchor, constant: 48),
            bottom.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            heightAnchor.constraint(equalToConstant: 102),
            playPauseButton.heightAnchor.constraint(equalTo: sampleSkip.heightAnchor),
            playPauseButton.widthAnchor.constraint(equalTo: sampleSkip.heightAnchor),
            volumeButton.widthAnchor.constraint(equalTo: speedButton.widthAnchor),
            volumeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 52),
        ])
    }

    private func makeSkipStack(direction: Int) -> NSStackView {
        let steps = direction < 0
            ? WorkspaceVideoPlayerTransport.skipSteps.reversed()
            : WorkspaceVideoPlayerTransport.skipSteps
        let buttons = steps.map { seconds -> NSButton in
            let button = NSButton()
            configureTextButton(
                button,
                title: WorkspaceVideoPlayerTransport.skipLabel(for: seconds, direction: direction),
                tooltip: direction < 0 ? "快退" : "快进",
                action: #selector(skip(_:))
            )
            button.tag = Int((seconds * Double(direction)).rounded())
            button.toolTip = direction < 0 ? "快退 \(button.title.dropFirst())" : "快进 \(button.title.dropFirst())"
            return button
        }
        skipButtons.append(contentsOf: buttons)
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.setHuggingPriority(.required, for: .horizontal)
        stack.setContentCompressionResistancePriority(.required, for: .horizontal)
        return stack
    }

    private func configureTextButton(_ button: NSButton, title: String, tooltip: String, action: Selector) {
        button.title = title
        button.bezelStyle = .flexiblePush
        button.controlSize = .regular
        button.setButtonType(.momentaryPushIn)
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
    }

    private func refreshProgressEnabled() {
        progressSlider.isEnabled = playPauseButton.isEnabled && duration != nil
    }

    @objc private func togglePlay() {
        dismissAccessoryPopovers()
        onTogglePlay?()
    }

    @objc private func skip(_ sender: NSButton) {
        dismissAccessoryPopovers()
        onSkip?(TimeInterval(sender.tag))
    }

    @objc private func toggleVolumePopover() {
        if volumePopover.isShown {
            volumePopover.close()
            return
        }
        speedPopover.close()
        volumePopover.show(from: volumeButton, value: Double(volume), label: volumeButton.title)
    }

    @objc private func toggleSpeedPopover() {
        if speedPopover.isShown {
            speedPopover.close()
            return
        }
        volumePopover.close()
        speedPopover.show(
            from: speedButton,
            value: Double(WorkspaceVideoPlayerTransport.rateIndex(rate)),
            label: speedButton.title
        )
    }

    @objc private func progressChanged(_ sender: NSSlider) {
        dismissAccessoryPopovers()
        isScrubbing = NSEvent.pressedMouseButtons != 0
        if let duration {
            currentTimeLabel.stringValue = WorkspaceVideoPlayerTransport.formatClock(sender.doubleValue * duration)
        }
        if !isScrubbing {
            onSeekFraction?(sender.doubleValue)
        }
    }

    private static func makeTimeLabel(alignment: NSTextAlignment) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .labelColor
        label.alignment = alignment
        label.isSelectable = false
        return label
    }
}

@MainActor
private final class KnitVideoPlayerSliderPopover: NSObject {
    var onChange: ((Double) -> Void)?

    private let popover = NSPopover()
    private let slider = NSSlider()
    private let label = NSTextField(labelWithString: "")
    private let mapsToRateIndex: Bool

    var isShown: Bool {
        popover.isShown
    }

    static func volume() -> KnitVideoPlayerSliderPopover {
        KnitVideoPlayerSliderPopover(
            minValue: 0,
            maxValue: 1,
            tickCount: 0,
            snapToTicks: false,
            mapsToRateIndex: false
        )
    }

    static func speed() -> KnitVideoPlayerSliderPopover {
        KnitVideoPlayerSliderPopover(
            minValue: 0,
            maxValue: Double(WorkspaceVideoPlayerTransport.rates.count - 1),
            tickCount: WorkspaceVideoPlayerTransport.rates.count,
            snapToTicks: true,
            mapsToRateIndex: true
        )
    }

    private init(
        minValue: Double,
        maxValue: Double,
        tickCount: Int,
        snapToTicks: Bool,
        mapsToRateIndex: Bool
    ) {
        self.mapsToRateIndex = mapsToRateIndex
        super.init()
        slider.minValue = minValue
        slider.maxValue = maxValue
        slider.numberOfTickMarks = tickCount
        slider.allowsTickMarkValuesOnly = snapToTicks
        slider.isVertical = true
        slider.controlSize = .small
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.alignment = .center
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(label)
        root.addSubview(slider)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: root.topAnchor, constant: 6),
            label.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -4),
            slider.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
            slider.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            slider.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -6),
            slider.heightAnchor.constraint(equalToConstant: 72),
            root.widthAnchor.constraint(equalToConstant: 44),
        ])

        let controller = NSViewController()
        controller.view = root
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = false

        slider.target = self
        slider.action = #selector(sliderChanged)
    }

    func show(from button: NSView, value: Double, label text: String) {
        setValue(value, label: text)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        placeAbove(button)
    }

    private func placeAbove(_ button: NSView) {
        guard let popoverWindow = popover.contentViewController?.view.window,
              let buttonWindow = button.window
        else { return }
        let buttonScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = popoverWindow.frame.size
        popoverWindow.setFrameOrigin(
            NSPoint(
                x: buttonScreen.midX - size.width / 2,
                y: buttonScreen.maxY + 4
            )
        )
    }

    func close() {
        popover.performClose(nil)
    }

    func setValue(_ value: Double, label text: String) {
        slider.doubleValue = value
        label.stringValue = text
    }

    @objc private func sliderChanged() {
        if mapsToRateIndex {
            let index = min(max(Int(slider.doubleValue.rounded()), 0), WorkspaceVideoPlayerTransport.rates.count - 1)
            slider.doubleValue = Double(index)
            label.stringValue = WorkspaceVideoPlayerTransport.rateLabel(WorkspaceVideoPlayerTransport.rates[index])
        } else {
            label.stringValue = "\(Int((min(max(slider.doubleValue, 0), 1) * 100).rounded()))%"
        }
        onChange?(slider.doubleValue)
    }
}
