import UIKit

final class ReaderViewController: StudioPageViewController, UITextViewDelegate {
    private let selection = VoiceSelectionButton()
    private let editor = UITextView()
    private let placeholder = StudioTheme.label("写一段话、粘贴一段故事……", size: 16, color: StudioTheme.secondary)
    private let characterCount = StudioTheme.label("0 字", size: 12, color: StudioTheme.secondary)
    private let saveState = StudioTheme.label("文稿仅保存在此设备", size: 11, color: StudioTheme.secondary)
    private let draftKey = "voices.reader.draft"
    private let exampleText = "傍晚的风穿过树梢，城市慢慢安静下来。我们沿着熟悉的小路往前走，把今天的小事，讲给明天的自己听。"
    private let exampleButton = UIButton(type: .system)
    private lazy var generateButton = StudioTheme.button("生成朗读演示", icon: "sparkles") { [weak self] in self?.generate() }
    private lazy var cancelButton = StudioTheme.button("取消生成", primary: false) { [weak self] in self?.cancelGeneration() }
    private let progress = UIProgressView(progressViewStyle: .default)
    private let generationLabel = StudioTheme.label("正在准备朗读…", size: 16, weight: .semibold)
    private lazy var generationCard = StudioTheme.card([
        generationLabel,
        StudioTheme.label("交互演示 · 无真实音频", size: 12, color: StudioTheme.warning),
        progress,
        cancelButton
    ])
    private let resultVoice = StudioTheme.label("", size: 13, color: StudioTheme.secondary)
    private let resultText = StudioTheme.label("", size: 14)
    private let outdated = StudioTheme.label("内容或声音已更改，请重新生成。", size: 12, color: StudioTheme.warning)
    private let playbackStatus = StudioTheme.label("播放进度演示 · 尚未开始", size: 12, color: StudioTheme.secondary)
    private let positionLabel = StudioTheme.label("00:00", size: 11, color: StudioTheme.secondary)
    private let durationLabel = StudioTheme.label("00:00", size: 11, color: StudioTheme.secondary)
    private let seek = UISlider()
    private lazy var playButton = StudioTheme.button("播放演示", icon: "play.fill", primary: false) { [weak self] in self?.togglePlayback() }
    private lazy var resultCard = makeResultCard()
    private var demo = ReaderDemoSession()
    private var timer: Timer?
    private var lastTick: TimeInterval = 0
    private var wasPlayingBeforeSeek = false
    private var selectedVoiceID: UUID?

    override func viewDidLoad() {
        super.viewDidLoad()
        addHeader("文字朗读", subtitle: "让文字，用你的声音说出来。", number: "03")
        selection.refresh()
        selectedVoiceID = VoiceLibraryStore.shared.selectedID
        selection.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.pausePlayback()
            self.selection.presentChoices(from: self)
        }, for: .touchUpInside)
        content.addArrangedSubview(StudioTheme.stack([
            StudioTheme.label("使用的声音", size: 12, color: StudioTheme.secondary), selection
        ], spacing: 10))
        configureEditor()
        exampleButton.setTitle("填入一段示例", for: .normal)
        exampleButton.tintColor = StudioTheme.accent
        exampleButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        exampleButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        exampleButton.accessibilityIdentifier = "reader.example"
        exampleButton.addAction(UIAction { [weak self] _ in self?.insertExample() }, for: .touchUpInside)
        let footer = StudioTheme.stack([exampleButton, UIView(), characterCount], axis: .horizontal)
        footer.alignment = .center
        content.addArrangedSubview(StudioTheme.card([
            StudioTheme.label("想读点什么？", size: 13, color: StudioTheme.secondary), editor, footer
        ], spacing: 8))
        generateButton.accessibilityIdentifier = "reader.generate"
        cancelButton.accessibilityIdentifier = "reader.cancelGeneration"
        progress.progressTintColor = StudioTheme.accent
        progress.trackTintColor = StudioTheme.raised
        progress.accessibilityLabel = "生成流程演示进度"
        content.addArrangedSubview(generateButton)
        generationCard.isHidden = true
        resultCard.isHidden = true
        content.addArrangedSubview(generationCard)
        content.addArrangedSubview(resultCard)
        content.addArrangedSubview(StudioTheme.stack([
            StudioTheme.label("交互演示 · 无真实音频", size: 12, weight: .medium, color: StudioTheme.warning),
            StudioTheme.label("AI 文字朗读待接入。现在可以体验生成与播放流程，文稿会自动保存到本机。", size: 12, color: StudioTheme.secondary),
            saveState
        ], spacing: 7))
        NotificationCenter.default.addObserver(self, selector: #selector(voiceLibraryChanged), name: .voiceLibraryDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationEnteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        updateDraftStatus()
    }

    isolated deinit { timer?.invalidate() }

    private func configureEditor() {
        editor.backgroundColor = .clear
        editor.textColor = StudioTheme.text
        editor.tintColor = StudioTheme.accent
        editor.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: 16))
        editor.adjustsFontForContentSizeCategory = true
        editor.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        editor.textContainer.lineFragmentPadding = 0
        editor.heightAnchor.constraint(equalToConstant: 170).isActive = true
        editor.delegate = self
        editor.accessibilityLabel = "朗读文稿"
        editor.accessibilityIdentifier = "reader.editor"
        editor.keyboardAppearance = .dark
        editor.text = UserDefaults.standard.string(forKey: draftKey) ?? ""
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.isUserInteractionEnabled = false
        placeholder.isAccessibilityElement = false
        editor.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.leadingAnchor.constraint(equalTo: editor.frameLayoutGuide.leadingAnchor),
            placeholder.trailingAnchor.constraint(equalTo: editor.frameLayoutGuide.trailingAnchor),
            placeholder.topAnchor.constraint(equalTo: editor.frameLayoutGuide.topAnchor, constant: 8)
        ])
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.barStyle = .black
        toolbar.tintColor = StudioTheme.accent
        toolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(endEditing))
        ]
        editor.inputAccessoryView = toolbar
    }

    private func makeResultCard() -> UIStackView {
        resultText.numberOfLines = 3
        outdated.isHidden = true
        seek.minimumTrackTintColor = StudioTheme.accent
        seek.maximumTrackTintColor = StudioTheme.border
        seek.thumbTintColor = StudioTheme.accent
        seek.accessibilityLabel = "朗读演示进度"
        seek.accessibilityIdentifier = "reader.seek"
        seek.addTarget(self, action: #selector(beginSeeking), for: .touchDown)
        seek.addTarget(self, action: #selector(seekChanged), for: .valueChanged)
        seek.addTarget(self, action: #selector(endSeeking), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        positionLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let times = StudioTheme.stack([positionLabel, UIView(), durationLabel], axis: .horizontal)
        playButton.accessibilityIdentifier = "reader.play"
        return StudioTheme.card([
            StudioTheme.label("朗读结果 · 演示", size: 17, weight: .semibold),
            StudioTheme.badge("交互演示 · 无真实音频", color: StudioTheme.warning),
            resultVoice, resultText, outdated,
            StudioTheme.stack([seek, times], spacing: 2),
            playButton, playbackStatus
        ], spacing: 12)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        selection.refresh()
        updateDraftStatus()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        view.endEditing(true)
        stopTransientWork()
    }

    @objc private func applicationEnteredBackground() { stopTransientWork() }
    @objc private func endEditing() { view.endEditing(true) }

    @objc private func voiceLibraryChanged() {
        let current = VoiceLibraryStore.shared.selectedID
        if selectedVoiceID != current { stopTransientWork() }
        selectedVoiceID = current
        selection.refresh()
        updateDraftStatus()
    }

    func textViewDidChange(_ textView: UITextView) {
        UserDefaults.standard.set(editor.text, forKey: draftKey)
        updateDraftStatus()
    }

    private func updateDraftStatus() {
        let count = editor.text.count
        placeholder.isHidden = count > 0
        characterCount.text = "\(count) 字"
        saveState.text = count > 0 ? "草稿已自动保存到本机" : "文稿仅保存在此设备"
        generateButton.isEnabled = !editor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !demo.isGenerating
        outdated.isHidden = !demo.isResultOutdated(text: editor.text, selectedVoiceID: VoiceLibraryStore.shared.selectedID)
    }

    private func insertExample() {
        let fill = { [weak self] in
            guard let self else { return }
            self.editor.text = self.exampleText
            self.textViewDidChange(self.editor)
        }
        guard !editor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, editor.text != exampleText else { fill(); return }
        let alert = UIAlertController(title: "替换当前文稿？", message: "填入示例会覆盖现在的草稿。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "替换", style: .destructive) { _ in fill() })
        present(alert, animated: true)
    }

    private func generate() {
        guard !demo.isGenerating, !editor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        view.endEditing(true)
        guard let voice = VoiceLibraryStore.shared.selectedSample else {
            selection.presentChoices(from: self)
            return
        }
        demo.generate(text: editor.text, voiceID: voice.id, voiceName: voice.name)
        updateGenerationUI()
        updatePlaybackUI()
        startTimerIfNeeded()
        view.layoutIfNeeded()
        scrollView.scrollRectToVisible(generationCard.convert(generationCard.bounds, to: scrollView), animated: true)
    }

    private func cancelGeneration() {
        demo.cancelGeneration()
        stopTimerIfIdle()
        updateGenerationUI()
        UIAccessibility.post(notification: .announcement, argument: "已取消生成演示")
    }

    private func updateGenerationUI() {
        generationCard.isHidden = !demo.isGenerating
        progress.progress = Float(demo.generationProgress)
        selection.isEnabled = !demo.isGenerating
        exampleButton.isEnabled = !demo.isGenerating
        editor.isEditable = !demo.isGenerating
        playButton.isEnabled = !demo.isGenerating
        seek.isEnabled = !demo.isGenerating
        generateButton.configuration?.title = demo.isGenerating ? "生成流程演示中…" : (demo.result == nil ? "生成朗读演示" : "重新生成演示")
        updateDraftStatus()
    }

    private func showResult() {
        guard let result = demo.result else { return }
        resultVoice.text = "\(result.voiceName) · \(result.text.count) 字"
        resultText.text = result.text
        resultText.accessibilityLabel = "生成时的文稿：\(result.text)"
        seek.maximumValue = Float(result.duration)
        durationLabel.text = StudioTheme.time(result.duration)
        resultCard.isHidden = false
        updateGenerationUI()
        updatePlaybackUI()
        view.layoutIfNeeded()
        scrollView.scrollRectToVisible(resultCard.convert(resultCard.bounds, to: scrollView), animated: true)
        UIAccessibility.post(notification: .announcement, argument: "朗读演示已准备好，无真实音频")
    }

    private func togglePlayback() {
        demo.togglePlayback()
        updatePlaybackUI()
        startTimerIfNeeded()
        stopTimerIfIdle()
    }

    private func pausePlayback() {
        demo.pause()
        wasPlayingBeforeSeek = false
        updatePlaybackUI()
        stopTimerIfIdle()
    }

    private func updatePlaybackUI() {
        guard let result = demo.result else { return }
        positionLabel.text = StudioTheme.time(result.position)
        if !seek.isTracking { seek.value = Float(result.position) }
        seek.accessibilityValue = "\(StudioTheme.time(result.position))，共 \(StudioTheme.time(result.duration))，交互演示"
        let title = result.isPlaying ? "暂停演示" : (result.position >= result.duration ? "重新播放演示" : "播放演示")
        playButton.configuration?.title = title
        playButton.configuration?.image = UIImage(systemName: result.isPlaying ? "pause.fill" : "play.fill")
        playbackStatus.text = result.isPlaying ? "正在演示播放进度 · 无真实音频" : (result.position >= result.duration ? "演示结束 · 无真实音频" : "播放进度演示 · 无真实音频")
    }

    @objc private func beginSeeking() {
        wasPlayingBeforeSeek = demo.result?.isPlaying == true
        demo.pause()
        stopTimerIfIdle()
    }

    @objc private func seekChanged() {
        demo.seek(to: TimeInterval(seek.value))
        updatePlaybackUI()
    }

    @objc private func endSeeking() {
        if wasPlayingBeforeSeek, let result = demo.result, result.position < result.duration {
            demo.togglePlayback()
        }
        wasPlayingBeforeSeek = false
        updatePlaybackUI()
        startTimerIfNeeded()
    }

    private func stopTransientWork() {
        demo.cancelGeneration()
        demo.pause()
        wasPlayingBeforeSeek = false
        timer?.invalidate()
        timer = nil
        updateGenerationUI()
        updatePlaybackUI()
    }

    private func startTimerIfNeeded() {
        guard timer == nil, demo.needsTimer else { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopTimerIfIdle() {
        guard !demo.needsTimer else { return }
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let completedGeneration = demo.advance(by: max(0, now - lastTick))
        lastTick = now
        if completedGeneration { showResult() }
        else if demo.isGenerating { progress.progress = Float(demo.generationProgress) }
        else { updatePlaybackUI() }
        stopTimerIfIdle()
    }
}
