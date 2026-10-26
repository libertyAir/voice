import UIKit

final class VoicePickerViewController: StudioPageViewController {
    var onCreate: (() -> Void)?
    private let samples = StudioTheme.stack(spacing: 10)

    override func viewDidLoad() {
        super.viewDidLoad()
        let close = StudioTheme.iconButton("xmark", label: "关闭声音选择") { [weak self] in self?.dismiss(animated: true) }
        let header = StudioTheme.stack([StudioTheme.label("选择声音", size: 23, weight: .semibold), UIView(), close], axis: .horizontal)
        header.alignment = .center
        content.addArrangedSubview(header)
        content.addArrangedSubview(StudioTheme.label("选择真实原声样本。AI 音色克隆待接入。", size: 13, color: StudioTheme.secondary))
        content.addArrangedSubview(samples)
        let create = StudioTheme.button("录制新的声音", icon: "plus", primary: false) { [weak self] in
            guard let self else { return }
            let completion = self.onCreate
            self.dismiss(animated: true, completion: completion)
        }
        create.accessibilityIdentifier = "voicePicker.create"
        content.addArrangedSubview(create)
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .voiceLibraryDidChange, object: nil)
        reload()
    }

    @objc private func reload() {
        samples.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let store = VoiceLibraryStore.shared
        if store.samples.isEmpty {
            samples.addArrangedSubview(StudioTheme.label("还没有声音，先录制一段吧。", color: StudioTheme.secondary))
        }
        for sample in store.samples {
            let selected = sample.id == store.selectedID
            let button = StudioTheme.button(sample.name, icon: selected ? "checkmark.circle.fill" : "person.crop.circle", primary: false) { [weak self] in
                store.select(sample)
                if let error = store.loadError { self?.showMessage(error, title: "声音选择未保存") }
                else { self?.dismiss(animated: true) }
            }
            button.contentHorizontalAlignment = .leading
            button.configuration?.subtitle = "原声样本 · \(StudioTheme.time(sample.duration))"
            button.configuration?.titleLineBreakMode = .byWordWrapping
            button.configuration?.baseForegroundColor = selected ? StudioTheme.accent : StudioTheme.text
            button.accessibilityIdentifier = "voicePicker.sample"
            if selected { button.accessibilityTraits.insert(.selected) }
            samples.addArrangedSubview(button)
        }
    }
}
