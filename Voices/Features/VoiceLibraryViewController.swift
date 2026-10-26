import UIKit

final class VoiceLibraryViewController: StudioPageViewController {
    private let store = VoiceLibraryStore.shared
    private let player = AudioPlaybackService()
    private let samplesStack = StudioTheme.stack(spacing: 12)
    private let countLabel = StudioTheme.label("0 个样本", size: 12, color: StudioTheme.secondary)
    private var playingID: UUID?
    private let emptyArea = StudioTheme.stack(spacing: 18)
    private let libraryArea = StudioTheme.stack(spacing: 14)
    private var activeWaveform: WaveformView?

    override func viewDidLoad() {
        super.viewDidLoad()
        addHeader("我的声音", subtitle: "把熟悉的音色，带到每一次表达。", number: "01")
        let title = StudioTheme.label("从一段录音开始", size: 21, weight: .semibold)
        title.textAlignment = .center
        let description = StudioTheme.label("读一小段文字，留下你的音色。\n下一次表达，由你赋予新的语气。", size: 14, color: StudioTheme.secondary)
        description.textAlignment = .center
        let record = StudioTheme.button("录制我的声音", icon: "mic") { [weak self] in self?.openRecorder() }
        record.accessibilityIdentifier = "library.record"
        let welcome = StudioTheme.card([VoiceIdentityView(), title, description, record], spacing: 20)
        welcome.layer.borderWidth = 0
        emptyArea.addArrangedSubview(welcome)
        emptyArea.addArrangedSubview(StudioTheme.note("录制真实原声，仅保存在此设备。AI 声音克隆待接入。", icon: "lock"))
        content.addArrangedSubview(emptyArea)
        let heading = StudioTheme.stack([StudioTheme.label("声音库", size: 13, color: StudioTheme.secondary), UIView(), countLabel], axis: .horizontal)
        heading.alignment = .center
        libraryArea.addArrangedSubview(heading)
        libraryArea.addArrangedSubview(samplesStack)
        let add = StudioTheme.button("添加声音", icon: "plus", primary: false) { [weak self] in self?.openRecorder() }
        add.accessibilityIdentifier = "library.add"
        libraryArea.addArrangedSubview(add)
        libraryArea.addArrangedSubview(StudioTheme.note("可在「实时变声」和「文字朗读」里选择这些原声样本。AI 声音克隆待接入。"))
        content.addArrangedSubview(libraryArea)
        player.onUpdate = { [weak self] _, _, level in self?.activeWaveform?.append(level) }
        player.onFinish = { [weak self] in self?.playingID = nil; self?.reloadSamples() }
        player.onError = { [weak self] message in
            self?.playingID = nil
            self?.reloadSamples()
            self?.showAudioError(message)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(reloadSamples), name: .voiceLibraryDidChange, object: nil)
        reloadSamples()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let error = store.loadError { showMessage(error, title: "声音库读取提示") }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player.stop()
        playingID = nil
        reloadSamples()
    }

    private func openRecorder() {
        player.stop()
        playingID = nil
        reloadSamples()
        presentVoiceRecorder()
    }

    @objc private func reloadSamples() {
        samplesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        activeWaveform = nil
        countLabel.text = "\(store.samples.count) 个样本"
        emptyArea.isHidden = !store.samples.isEmpty
        libraryArea.isHidden = store.samples.isEmpty
        for sample in store.samples { samplesStack.addArrangedSubview(sampleCard(sample)) }
    }

    private func sampleCard(_ sample: VoiceSample) -> UIView {
        let selected = store.selectedID == sample.id
        let title = StudioTheme.label(sample.name, size: 15, weight: .semibold)
        let date = DateFormatter.localizedString(from: sample.createdAt, dateStyle: .short, timeStyle: .none)
        let subtitle = StudioTheme.label("原声样本  ·  \(StudioTheme.time(sample.duration))  ·  \(date)", size: 12, color: StudioTheme.secondary)
        let more = UIButton(type: .system)
        more.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        more.tintColor = StudioTheme.secondary
        more.widthAnchor.constraint(equalToConstant: 44).isActive = true
        more.heightAnchor.constraint(equalToConstant: 44).isActive = true
        more.accessibilityLabel = "管理\(sample.name)"
        more.addAction(UIAction { [weak self, weak more] _ in
            guard let more else { return }
            self?.manage(sample, source: more)
        }, for: .touchUpInside)
        let heading = StudioTheme.stack([StudioTheme.stack([title, subtitle], spacing: 6), more], axis: .horizontal)
        heading.alignment = .center
        let play = StudioTheme.button(playingID == sample.id ? "停止" : "试听", icon: playingID == sample.id ? "stop.fill" : "play.fill", primary: false) { [weak self] in
            self?.togglePlayback(sample)
        }
        play.accessibilityIdentifier = "sample.play"
        let choose = StudioTheme.button(selected ? "当前声音" : "使用声音", icon: selected ? "checkmark.circle.fill" : "circle", primary: false) { [weak self] in
            guard let self else { return }
            self.store.select(sample)
            if let error = self.store.loadError { self.showMessage(error, title: "声音选择未保存") }
        }
        choose.accessibilityIdentifier = "sample.select"
        if selected { choose.accessibilityTraits.insert(.selected) }
        choose.configuration?.baseForegroundColor = selected ? StudioTheme.accent : StudioTheme.secondary
        let actions = StudioTheme.stack([play, choose], spacing: 10, axis: .horizontal)
        actions.distribution = .fillEqually
        let wave = WaveformView(height: 42)
        wave.isAccessibilityElement = playingID == sample.id
        if playingID == sample.id { activeWaveform = wave }
        let card = StudioTheme.card([heading, wave, actions], spacing: 12)
        card.layer.borderColor = (selected ? StudioTheme.accent.withAlphaComponent(0.75) : StudioTheme.border).cgColor
        return card
    }

    private func togglePlayback(_ sample: VoiceSample) {
        if playingID == sample.id {
            player.stop()
            playingID = nil
        } else {
            do {
                try player.play(url: store.fileURL(for: sample))
                playingID = sample.id
            } catch { playingID = nil; showAudioError(error.localizedDescription) }
        }
        reloadSamples()
    }

    private func manage(_ sample: VoiceSample, source: UIView) {
        let alert = UIAlertController(title: sample.name, message: "管理此设备中的原声样本", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "重命名", style: .default) { [weak self] _ in self?.rename(sample) })
        alert.addAction(UIAlertAction(title: "删除样本", style: .destructive) { [weak self] _ in self?.confirmDelete(sample) })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.popoverPresentationController?.sourceView = source
        alert.popoverPresentationController?.sourceRect = source.bounds
        present(alert, animated: true)
    }

    private func rename(_ sample: VoiceSample) {
        let alert = UIAlertController(title: "重命名声音样本", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = sample.name; $0.placeholder = "样本名称"; $0.clearButtonMode = .whileEditing }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            do { try self?.store.rename(sample, to: alert?.textFields?.first?.text ?? "") }
            catch { DispatchQueue.main.async { self?.showMessage(error.localizedDescription) } }
        })
        present(alert, animated: true)
    }

    private func confirmDelete(_ sample: VoiceSample) {
        let alert = UIAlertController(title: "删除“\(sample.name)”？", message: "这会删除此设备上的样本和录音文件，无法恢复。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            guard let self else { return }
            if self.playingID == sample.id { self.player.stop(); self.playingID = nil }
            do { try self.store.delete(sample) }
            catch { DispatchQueue.main.async { self.showMessage(error.localizedDescription) } }
        })
        present(alert, animated: true)
    }
}
