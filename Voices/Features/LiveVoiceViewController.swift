import UIKit

final class LiveVoiceViewController: StudioPageViewController {
    private let selection = VoiceSelectionButton()
    private let recorder = AudioRecorderService()
    private let player = AudioPlaybackService()
    private let waveform = WaveformView(height: 78)
    private let status = StudioTheme.label("准备开始", size: 12, color: StudioTheme.secondary)
    private let timerLabel = StudioTheme.label("00:00", size: 38, weight: .light)
    private let recordHint = StudioTheme.label("点击开始原声试录", size: 14, weight: .medium)
    private let clipActions = StudioTheme.stack(spacing: 10)
    private var clip: RecordedClip?
    private var isFinishingRecording = false
    private lazy var recordButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = StudioTheme.accent
        configuration.baseForegroundColor = StudioTheme.background
        configuration.image = UIImage(systemName: "mic.fill")
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        configuration.cornerStyle = .capsule
        let button = UIButton(configuration: configuration)
        button.addAction(UIAction { [weak self] _ in self?.toggleRecording() }, for: .touchUpInside)
        button.accessibilityIdentifier = "live.record"
        button.accessibilityLabel = "开始原声试录"
        button.accessibilityHint = "采集真实麦克风音频，当前不会转换音色"
        return button
    }()
    private lazy var playbackButton = StudioTheme.button("回放原声", icon: "play.fill", primary: false) { [weak self] in self?.togglePlayback() }
    private lazy var saveButton = StudioTheme.button("保存到我的声音", icon: "plus", primary: false) { [weak self] in self?.saveClip() }

    override func viewDidLoad() {
        super.viewDidLoad()
        addHeader("实时变声", subtitle: "保留你的语气和节奏，换一种声音。", number: "02")
        selection.refresh()
        selection.addAction(UIAction { [weak self] _ in self?.chooseVoice() }, for: .touchUpInside)
        content.addArrangedSubview(StudioTheme.stack([
            StudioTheme.label("使用的声音", size: 12, color: StudioTheme.secondary), selection
        ], spacing: 10))

        timerLabel.textAlignment = .center
        timerLabel.font = UIFontMetrics.default.scaledFont(for: .monospacedDigitSystemFont(ofSize: 38, weight: .light))
        timerLabel.accessibilityIdentifier = "live.time"
        status.textAlignment = .center
        status.accessibilityIdentifier = "live.status"
        recordHint.textAlignment = .center
        let buttonContainer = UIView()
        let halo = UIView()
        halo.backgroundColor = StudioTheme.accent.withAlphaComponent(0.06)
        halo.layer.cornerRadius = 46
        halo.isUserInteractionEnabled = false
        halo.translatesAutoresizingMaskIntoConstraints = false
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.addSubview(halo)
        buttonContainer.addSubview(recordButton)
        NSLayoutConstraint.activate([
            buttonContainer.heightAnchor.constraint(equalToConstant: 96),
            halo.widthAnchor.constraint(equalToConstant: 92), halo.heightAnchor.constraint(equalTo: halo.widthAnchor),
            halo.centerXAnchor.constraint(equalTo: buttonContainer.centerXAnchor), halo.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),
            recordButton.widthAnchor.constraint(equalToConstant: 76), recordButton.heightAnchor.constraint(equalTo: recordButton.widthAnchor),
            recordButton.centerXAnchor.constraint(equalTo: buttonContainer.centerXAnchor), recordButton.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor)
        ])
        let availability = StudioTheme.label("AI 变声待接入 · 当前为原声试录", size: 12, color: StudioTheme.warning)
        availability.textAlignment = .center
        let stage = StudioTheme.stack([timerLabel, status, waveform, buttonContainer, recordHint, availability], spacing: 10)
        stage.setCustomSpacing(16, after: status)
        content.addArrangedSubview(stage)

        playbackButton.accessibilityIdentifier = "live.play"
        saveButton.accessibilityIdentifier = "live.save"
        clipActions.addArrangedSubview(playbackButton)
        clipActions.addArrangedSubview(saveButton)
        clipActions.isHidden = true
        content.addArrangedSubview(clipActions)

        let concept = StudioTheme.label("你的语气 / 节奏   →   所选声音的音色", size: 12, color: StudioTheme.secondary)
        concept.textAlignment = .center
        let divider = UIView()
        divider.backgroundColor = StudioTheme.border
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        content.addArrangedSubview(StudioTheme.stack([divider, concept], spacing: 15))
        content.addArrangedSubview(StudioTheme.label("目标音色将在接入模型后生效。现在可以试录和回放原声；切换页面或进入后台会停止采集。", size: 12, color: StudioTheme.secondary))

        recorder.onUpdate = { [weak self] elapsed, level in
            self?.waveform.append(level)
            self?.timerLabel.text = StudioTheme.time(elapsed)
        }
        recorder.onInterruption = { [weak self] in
            guard let self else { return }
            self.finishRecording()
            self.status.text = self.clip == nil ? "录音已中断，请重新开始" : "录音已中断，可回放或保存"
        }
        recorder.onError = { [weak self] message in
            self?.finishRecording()
            self?.showAudioError(message)
        }
        player.onUpdate = { [weak self] elapsed, _, level in
            self?.waveform.append(level)
            self?.timerLabel.text = StudioTheme.time(elapsed)
        }
        player.onFinish = { [weak self] in self?.finishPlayback() }
        player.onError = { [weak self] message in self?.finishPlayback(); self?.showAudioError(message) }
        NotificationCenter.default.addObserver(self, selector: #selector(refreshSelection), name: .voiceLibraryDidChange, object: nil)
    }

    isolated deinit {
        if let clip { try? FileManager.default.removeItem(at: clip.url) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        selection.refresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopAudio()
    }

    @objc private func refreshSelection() {
        selection.refresh()
    }

    private func chooseVoice() {
        stopAudio()
        selection.presentChoices(from: self)
    }

    private func stopAudio() {
        if recorder.isRecording || recorder.isRequestingPermission { finishRecording() }
        if player.isPlaying { player.stop(); finishPlayback() }
    }

    private func toggleRecording() {
        if recorder.isRecording { finishRecording(); return }
        guard !recorder.isRequestingPermission else { return }
        guard VoiceLibraryStore.shared.selectedSample != nil else {
            chooseVoice()
            return
        }
        player.stop()
        finishPlayback()
        if clip != nil {
            let alert = UIAlertController(title: "重新试录？", message: "当前原声还没有保存。重新录制会替换这段录音。", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "保留录音", style: .cancel))
            alert.addAction(UIAlertAction(title: "重新试录", style: .destructive) { [weak self, weak alert] _ in
                alert?.dismiss(animated: true) { [weak self] in self?.beginRecording() }
            })
            present(alert, animated: true)
        } else {
            beginRecording()
        }
    }

    private func beginRecording() {
        player.stop()
        waveform.reset()
        timerLabel.text = "00:00"
        status.text = "正在准备麦克风…"
        clipActions.isHidden = true
        recordButton.isEnabled = false
        recordHint.text = "正在准备录音"
        recorder.start { [weak self] result in
            guard let self else { return }
            self.recordButton.isEnabled = true
            switch result {
            case .success:
                if let previous = self.clip { try? FileManager.default.removeItem(at: previous.url) }
                self.clip = nil
                self.recordButton.configuration?.image = UIImage(systemName: "stop.fill")
                self.recordButton.accessibilityLabel = "停止原声试录"
                self.recordHint.text = "点击结束试录"
                self.status.text = "正在采集原声 · 未转换音色"
                self.waveform.accessibilityValue = "正在显示真实麦克风音量"
            case .failure(let error):
                self.updateIdleControls()
                self.timerLabel.text = StudioTheme.time(self.clip?.duration ?? 0)
                self.status.text = self.clip == nil ? "麦克风尚未开始采集" : "新录音未开始，已保留上一段原声"
                if case .cancelled? = error as? VoiceAudioError { return }
                self.showAudioError(error.localizedDescription)
            }
        }
    }

    private func finishRecording() {
        guard !isFinishingRecording else { return }
        isFinishingRecording = true
        defer { isFinishingRecording = false }
        if let result = recorder.stop() { clip = result }
        updateIdleControls()
        timerLabel.text = StudioTheme.time(clip?.duration ?? 0)
        status.text = clip == nil ? "准备开始" : "试录完成 · 可回放或保存原声"
    }

    private func updateIdleControls() {
        recordButton.isEnabled = true
        recordButton.configuration?.image = UIImage(systemName: "mic.fill")
        recordButton.accessibilityLabel = clip == nil ? "开始原声试录" : "重新试录"
        recordHint.text = clip == nil ? "点击开始原声试录" : "点击重新试录"
        clipActions.isHidden = clip == nil
        playbackButton.configuration?.title = "回放原声"
        playbackButton.configuration?.image = UIImage(systemName: "play.fill")
    }

    private func togglePlayback() {
        guard let clip, !recorder.isRecording, !recorder.isRequestingPermission else { return }
        if player.isPlaying { player.stop(); finishPlayback(); return }
        do {
            try player.play(url: clip.url)
            waveform.reset()
            waveform.accessibilityValue = "正在显示原声回放音量"
            playbackButton.configuration?.title = "停止回放"
            playbackButton.configuration?.image = UIImage(systemName: "stop.fill")
            status.text = "正在回放原声 · 未转换音色"
        } catch {
            finishPlayback()
            showAudioError(error.localizedDescription)
        }
    }

    private func finishPlayback() {
        updateIdleControls()
        timerLabel.text = StudioTheme.time(clip?.duration ?? 0)
        status.text = clip == nil ? "准备开始" : "原声试录已就绪"
    }

    private func saveClip() {
        guard clip != nil else { return }
        player.stop()
        finishPlayback()
        let alert = UIAlertController(title: "保存到我的声音", message: "保存的是刚刚试录的真实原声，AI 声音克隆尚未接入。", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "声音名称"
            field.text = "我的声音 \(VoiceLibraryStore.shared.samples.count + 1)"
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        let saveAction = UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let alert else { return }
            let name = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            alert.dismiss(animated: true) { [weak self] in self?.persistClip(named: name) }
        }
        alert.addAction(saveAction)
        if let field = alert.textFields?.first {
            saveAction.isEnabled = !(field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            field.addAction(UIAction { [weak field, weak saveAction] _ in
                saveAction?.isEnabled = !(field?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }, for: .editingChanged)
        }
        present(alert, animated: true)
    }

    private func persistClip(named name: String) {
        guard let clip else { return }
        do {
            try VoiceLibraryStore.shared.addRecording(from: clip.url, name: name, duration: clip.duration)
            self.clip = nil
            waveform.reset()
            updateIdleControls()
            timerLabel.text = "00:00"
            status.text = "已保存到我的声音，并设为当前声音"
            UIAccessibility.post(notification: .announcement, argument: "原声已保存到我的声音")
        } catch {
            showMessage(error.localizedDescription, title: "保存失败")
        }
    }
}
