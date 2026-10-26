import UIKit

final class RecordingViewController: StudioPageViewController, UIAdaptivePresentationControllerDelegate {
    private let recorder = AudioRecorderService()
    private let player = AudioPlaybackService()
    private let waveform = WaveformView(height: 110)
    private let timeLabel = StudioTheme.label("00:00", size: 48, weight: .light)
    private let stateLabel = StudioTheme.label("准备好，就开始吧", size: 13, color: StudioTheme.secondary)
    private let nameField = UITextField()
    private let nameError = StudioTheme.label("给这个声音起个名字，再保存吧。", size: 12, color: .systemRed)
    private let scriptArea = StudioTheme.stack(spacing: 14)
    private let titleLabel = StudioTheme.label("录制我的声音", size: 24, weight: .semibold)
    private var clip: RecordedClip?
    private lazy var recordButton = StudioTheme.button("开始录音", icon: "mic.fill") { [weak self] in self?.toggleRecording() }
    private lazy var playButton = StudioTheme.button("试听原声", icon: "play.fill", primary: false) { [weak self] in self?.togglePlayback() }
    private lazy var saveButton = StudioTheme.button("保存声音", icon: "checkmark") { [weak self] in self?.save() }
    private let saveArea = StudioTheme.stack(spacing: 12)

    override func viewDidLoad() {
        super.viewDidLoad()
        presentationController?.delegate = self
        let close = StudioTheme.iconButton("xmark", label: "关闭录音") { [weak self] in self?.close() }
        close.accessibilityIdentifier = "recorder.close"
        let top = StudioTheme.stack([titleLabel, UIView(), close], axis: .horizontal)
        top.alignment = .center
        content.addArrangedSubview(top)
        content.addArrangedSubview(StudioTheme.note("真实录音，仅保存在此设备。找个安静的地方，自然说话。", icon: "lock"))
        timeLabel.textAlignment = .center
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 48, weight: .light)
        stateLabel.textAlignment = .center
        recordButton.accessibilityIdentifier = "recorder.toggle"
        playButton.accessibilityIdentifier = "recorder.play"
        scriptArea.addArrangedSubview(StudioTheme.card([
            StudioTheme.label("试着读一段", size: 12, weight: .medium, color: StudioTheme.secondary),
            StudioTheme.label("今天的阳光刚刚好。我想用自己的声音，讲一个故事，也留下一段属于我的回忆。", size: 17),
            StudioTheme.label("建议录制 30–60 秒，也可以自由表达。", size: 12, color: StudioTheme.secondary)
        ], spacing: 14))
        content.addArrangedSubview(scriptArea)
        content.addArrangedSubview(StudioTheme.stack([timeLabel, waveform, stateLabel, recordButton], spacing: 16))
        nameField.placeholder = "给声音样本起个名字"
        nameField.text = "我的声音 \(VoiceLibraryStore.shared.samples.count + 1)"
        nameField.textColor = StudioTheme.text
        nameField.backgroundColor = StudioTheme.raised
        nameField.layer.cornerRadius = 12
        nameField.font = .systemFont(ofSize: 16)
        nameField.heightAnchor.constraint(equalToConstant: 52).isActive = true
        nameField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        nameField.leftViewMode = .always
        nameField.clearButtonMode = .whileEditing
        nameField.returnKeyType = .done
        nameField.keyboardAppearance = .dark
        nameField.addAction(UIAction { [weak self] _ in self?.view.endEditing(true) }, for: .editingDidEndOnExit)
        nameField.addAction(UIAction { [weak self] _ in self?.nameError.isHidden = true }, for: .editingChanged)
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.barStyle = .black
        toolbar.tintColor = StudioTheme.accent
        toolbar.items = [UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil), UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(finishEditing))]
        nameField.inputAccessoryView = toolbar
        nameField.accessibilityIdentifier = "recorder.name"
        saveButton.accessibilityIdentifier = "recorder.save"
        nameError.isHidden = true
        nameError.accessibilityIdentifier = "recorder.nameError"
        [StudioTheme.label("给声音起个名字", size: 13, color: StudioTheme.secondary), nameField, nameError, playButton, saveButton].forEach { saveArea.addArrangedSubview($0) }
        saveArea.isHidden = true
        content.addArrangedSubview(saveArea)
        recorder.onUpdate = { [weak self] elapsed, level in
            self?.timeLabel.text = StudioTheme.time(elapsed)
            self?.waveform.append(level)
        }
        recorder.onInterruption = { [weak self] in
            self?.finishRecording()
            self?.stateLabel.text = "录音已中断，可试听并保存"
        }
        recorder.onError = { [weak self] message in
            self?.finishRecording()
            self?.showAudioError(message)
        }
        player.onUpdate = { [weak self] elapsed, _, level in
            self?.timeLabel.text = StudioTheme.time(elapsed)
            self?.waveform.append(level)
        }
        player.onFinish = { [weak self] in self?.finishPlayback() }
        player.onError = { [weak self] message in self?.finishPlayback(); self?.showAudioError(message) }
    }

    private func toggleRecording() {
        view.endEditing(true)
        if recorder.isRecording { finishRecording(); return }
        guard !recorder.isRequestingPermission else { return }
        if clip != nil {
            let alert = UIAlertController(title: "重新录制？", message: "当前尚未保存的录音将被替换。", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "重新录制", style: .destructive) { [weak self] _ in self?.beginRecording() })
            present(alert, animated: true)
        } else { beginRecording() }
    }
    @objc private func finishEditing() { view.endEditing(true) }

    private func beginRecording() {
        player.stop()
        finishPlayback()
        waveform.reset()
        timeLabel.text = "00:00"
        titleLabel.text = "录制我的声音"
        scriptArea.isHidden = false
        saveArea.isHidden = true
        recordButton.configuration?.baseBackgroundColor = StudioTheme.accent
        recordButton.configuration?.baseForegroundColor = StudioTheme.background
        isModalInPresentation = true
        recordButton.isEnabled = false
        stateLabel.text = "正在准备麦克风…"
        recorder.start { [weak self] result in
            guard let self else { return }
            self.recordButton.isEnabled = true
            switch result {
            case .success:
                self.removeClip()
                self.recordButton.configuration?.title = "停止录音"
                self.recordButton.configuration?.image = UIImage(systemName: "stop.fill")
                self.stateLabel.text = "正在录制 · 保持自然语速"
                self.waveform.accessibilityValue = "正在显示真实麦克风音量"
            case .failure(let error):
                self.finishRecording()
                self.stateLabel.text = self.clip == nil ? "录音尚未开始" : "新录音未开始，已保留上一段原声"
                if case .cancelled? = error as? VoiceAudioError { return }
                self.showAudioError(error.localizedDescription)
            }
        }
    }

    private func finishRecording() {
        if let result = recorder.stop() { clip = result }
        recordButton.isEnabled = true
        recordButton.configuration?.title = clip == nil ? "开始录音" : "重新录制"
        recordButton.configuration?.image = UIImage(systemName: "mic.fill")
        saveArea.isHidden = clip == nil
        scriptArea.isHidden = clip != nil
        titleLabel.text = clip == nil ? "录制我的声音" : "保存我的声音"
        recordButton.configuration?.baseBackgroundColor = clip == nil ? StudioTheme.accent : StudioTheme.raised
        recordButton.configuration?.baseForegroundColor = clip == nil ? StudioTheme.background : StudioTheme.text
        isModalInPresentation = clip != nil
        if let clip {
            timeLabel.text = StudioTheme.time(clip.duration)
            stateLabel.text = "录制完成 · 试听后保存"
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.view.layoutIfNeeded()
                self.scrollView.scrollRectToVisible(self.saveArea.convert(self.saveArea.bounds, to: self.scrollView), animated: true)
            }
        } else { stateLabel.text = "没有可保存的录音，请再试一次" }
    }

    private func togglePlayback() {
        guard let clip else { return }
        if player.isPlaying {
            player.pause()
            playButton.configuration?.title = "继续试听"
            playButton.configuration?.image = UIImage(systemName: "play.fill")
            stateLabel.text = "试听已暂停"
            return
        }
        do {
            if player.isPaused { try player.resume() }
            else { try player.play(url: clip.url); waveform.reset() }
            playButton.configuration?.title = "暂停试听"
            playButton.configuration?.image = UIImage(systemName: "pause.fill")
            stateLabel.text = "正在播放原声"
        } catch { finishPlayback(); showAudioError(error.localizedDescription) }
    }
    private func finishPlayback() {
        playButton.configuration?.title = "试听原声"
        playButton.configuration?.image = UIImage(systemName: "play.fill")
        stateLabel.text = "原声样本 · 可以保存"
        timeLabel.text = StudioTheme.time(clip?.duration ?? 0)
    }
    private func save() {
        guard let clip else { return }
        guard !(nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            nameError.isHidden = false
            nameField.becomeFirstResponder()
            UIAccessibility.post(notification: .announcement, argument: nameError.text)
            return
        }
        player.stop()
        finishPlayback()
        view.endEditing(true)
        do {
            _ = try VoiceLibraryStore.shared.addRecording(from: clip.url, name: nameField.text ?? "", duration: clip.duration)
            self.clip = nil
            dismiss(animated: true)
        } catch { showMessage(error.localizedDescription, title: "保存失败") }
    }
    private func close() {
        view.endEditing(true)
        guard recorder.isRecording || recorder.isRequestingPermission || clip != nil else { dismiss(animated: true); return }
        if recorder.isRecording || recorder.isRequestingPermission { finishRecording() }
        player.stop()
        finishPlayback()
        let alert = UIAlertController(title: "放弃这段录音？", message: "未保存的录音会被删除。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "继续编辑", style: .cancel))
        alert.addAction(UIAlertAction(title: "放弃", style: .destructive) { [weak self] _ in
            self?.recorder.discard()
            self?.player.stop()
            self?.removeClip()
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
    private func removeClip() {
        if let clip { try? FileManager.default.removeItem(at: clip.url) }
        clip = nil
    }
    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) { close() }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil {
            recorder.discard()
            player.stop()
            removeClip()
        }
    }
}
