import UIKit
import AVFoundation

enum StudioTheme {
    static let background = UIColor(red: 0.051, green: 0.063, blue: 0.082, alpha: 1)
    static let surface = UIColor(red: 0.090, green: 0.110, blue: 0.137, alpha: 1)
    static let raised = UIColor(red: 0.133, green: 0.161, blue: 0.196, alpha: 1)
    static let border = UIColor(red: 0.173, green: 0.208, blue: 0.251, alpha: 1)
    static let accent = UIColor(red: 0.612, green: 0.910, blue: 0.769, alpha: 1)
    static let purple = UIColor(red: 0.70, green: 0.64, blue: 1, alpha: 1)
    static let text = UIColor(red: 0.949, green: 0.953, blue: 0.945, alpha: 1)
    static let secondary = UIColor(red: 0.612, green: 0.655, blue: 0.702, alpha: 1)
    static let warning = UIColor(red: 0.95, green: 0.74, blue: 0.44, alpha: 1)

    static func label(_ text: String, size: CGFloat = 15, weight: UIFont.Weight = .regular, color: UIColor = StudioTheme.text) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: size, weight: weight))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        return label
    }
    static func button(_ title: String, icon: String? = nil, primary: Bool = true, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = icon.flatMap { UIImage(systemName: $0) }
        config.imagePadding = 9
        config.baseBackgroundColor = primary ? accent : raised
        config.baseForegroundColor = primary ? background : text
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 16)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { input in
            var result = input
            result.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
            return result
        }
        let button = UIButton(configuration: config)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        return button
    }
    static func stack(_ views: [UIView] = [], spacing: CGFloat = 14, axis: NSLayoutConstraint.Axis = .vertical) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = axis
        stack.spacing = spacing
        return stack
    }
    static func iconButton(_ icon: String, label: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: icon), for: .normal)
        button.tintColor = secondary
        button.backgroundColor = raised
        button.layer.cornerRadius = 22
        button.accessibilityLabel = label
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44)
        ])
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
    static func note(_ text: String, icon: String = "info.circle") -> UIView {
        let image = UIImageView(image: UIImage(systemName: icon))
        image.tintColor = secondary
        image.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: 15),
            image.heightAnchor.constraint(equalToConstant: 19)
        ])
        let row = stack([image, label(text, size: 12, color: secondary)], spacing: 8, axis: .horizontal)
        row.alignment = .top
        return row
    }
    static func card(_ views: [UIView], spacing: CGFloat = 14) -> UIStackView {
        let stack = self.stack(views, spacing: spacing)
        stack.backgroundColor = surface
        stack.layer.cornerRadius = 22
        stack.layer.borderWidth = 1
        stack.layer.borderColor = border.cgColor
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
        return stack
    }
    static func time(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
    static func badge(_ text: String, color: UIColor = secondary) -> UIView {
        let label = self.label(text, size: 11, weight: .semibold, color: color)
        let content = stack([label], spacing: 0)
        content.isLayoutMarginsRelativeArrangement = true
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        content.backgroundColor = color.withAlphaComponent(0.10)
        content.layer.cornerRadius = 10
        let row = stack([content, UIView()], axis: .horizontal)
        content.setContentHuggingPriority(.required, for: .horizontal)
        return row
    }
}

class StudioPageViewController: UIViewController {
    let content = StudioTheme.stack(spacing: 24)
    let scrollView = UIScrollView()
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = StudioTheme.background
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.addSubview(content)
        let width = content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -44)
        width.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
            content.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            scrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            content.widthAnchor.constraint(lessThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor, constant: -44),
            width, content.widthAnchor.constraint(lessThanOrEqualToConstant: 620)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(adjustForKeyboard(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }
    @objc private func adjustForKeyboard(_ notification: Notification) {
        guard view.window != nil,
              let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let local = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - local.minY - view.safeAreaInsets.bottom)
        let input = firstResponder(in: content)
        guard input != nil || overlap == 0 else { return }
        scrollView.contentInset.bottom = overlap
        scrollView.verticalScrollIndicatorInsets.bottom = overlap
        if let input {
            scrollView.scrollRectToVisible(input.convert(input.bounds, to: scrollView).insetBy(dx: 0, dy: -12), animated: true)
        }
    }
    private func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        return view.subviews.lazy.compactMap { self.firstResponder(in: $0) }.first
    }
    func addHeader(_ title: String, subtitle: String, number: String) {
        let symbol = UIImageView(image: UIImage(systemName: "waveform"))
        symbol.tintColor = StudioTheme.accent
        symbol.contentMode = .scaleAspectFit
        symbol.widthAnchor.constraint(equalToConstant: 23).isActive = true
        symbol.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let brand = StudioTheme.label("V O I C E S", size: 14, weight: .bold)
        let prototype = StudioTheme.label("业务原型", size: 11, color: StudioTheme.secondary)
        let top = StudioTheme.stack([symbol, brand, UIView(), prototype], spacing: 9, axis: .horizontal)
        top.alignment = .center
        let subtitles = ["01": "YOUR VOICE, REIMAGINED", "02": "SPEAK IN A NEW WAY", "03": "WORDS BECOME VOICE"]
        let eyebrow = StudioTheme.label(subtitles[number] ?? "VOICE STUDIO", size: 10, weight: .semibold, color: StudioTheme.accent)
        let heading = StudioTheme.label(title, size: 30, weight: .semibold)
        heading.accessibilityTraits = .header
        let titles = StudioTheme.stack([eyebrow, heading, StudioTheme.label(subtitle, size: 13, color: StudioTheme.secondary)], spacing: 8)
        content.addArrangedSubview(StudioTheme.stack([top, titles], spacing: 30))
    }
    func showMessage(_ message: String, title: String = "提示") {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        presentNotice(alert)
    }
    func showAudioError(_ message: String) {
        let alert = UIAlertController(title: "暂时无法使用音频", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好的", style: .cancel))
        if AVAudioSession.sharedInstance().recordPermission == .denied {
            alert.addAction(UIAlertAction(title: "打开设置", style: .default) { _ in
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            })
        }
        presentNotice(alert)
    }
    private func presentNotice(_ alert: UIAlertController, attempts: Int = 12) {
        guard viewIfLoaded?.window != nil else { return }
        if let presented = presentedViewController {
            // Alert action handlers may report a failure before UIKit finishes dismissing the alert.
            guard presented is UIAlertController, attempts > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.presentNotice(alert, attempts: attempts - 1)
            }
            return
        }
        present(alert, animated: true)
    }
}

/// Shows measured audio levels; idle input stays flat.
final class WaveformView: UIView {
    var color = StudioTheme.accent
    private var levels = Array(repeating: CGFloat(0), count: 52)
    init(height: CGFloat = 88) {
        super.init(frame: .zero)
        backgroundColor = .clear
        heightAnchor.constraint(equalToConstant: height).isActive = true
        isAccessibilityElement = true
        accessibilityLabel = "音频波形"
        accessibilityValue = "等待音频输入"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func append(_ level: Float) {
        levels.removeFirst()
        levels.append(CGFloat(max(0, min(1, level))))
        setNeedsDisplay()
    }
    func reset() {
        levels = Array(repeating: 0, count: 52)
        accessibilityValue = "等待音频输入"
        setNeedsDisplay()
    }
    override func draw(_ rect: CGRect) {
        let step = rect.width / CGFloat(levels.count)
        for (index, level) in levels.enumerated() {
            let h = max(3, level * (rect.height - 12))
            color.withAlphaComponent(level > 0.02 ? 0.95 : 0.25).setFill()
            UIBezierPath(roundedRect: CGRect(x: CGFloat(index) * step, y: (rect.height - h) / 2, width: max(2, step - 3), height: h), cornerRadius: 2).fill()
        }
    }
}

final class VoiceSelectionButton: UIButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: .voiceLibraryDidChange, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func libraryChanged() { refresh() }

    func refresh() {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = StudioTheme.surface
        config.baseForegroundColor = StudioTheme.text
        config.title = VoiceLibraryStore.shared.selectedSample?.name ?? "还没有声音"
        config.subtitle = VoiceLibraryStore.shared.selectedSample == nil ? "点击录制，创建你的第一个声音" : "本地原声 · 点击切换 · AI 待接入"
        config.image = UIImage(systemName: "person.crop.circle")
        config.imagePadding = 14
        config.titlePadding = 5
        config.titleLineBreakMode = .byWordWrapping
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var result = attributes
            result.font = UIFont.preferredFont(forTextStyle: .subheadline)
            return result
        }
        config.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var result = attributes
            result.foregroundColor = StudioTheme.secondary
            result.font = UIFont.preferredFont(forTextStyle: .caption1)
            return result
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        config.cornerStyle = .medium
        config.background.strokeColor = StudioTheme.border
        config.background.strokeWidth = 1
        configuration = config
        contentHorizontalAlignment = .leading
        accessibilityLabel = "选择声音样本"
        accessibilityValue = VoiceLibraryStore.shared.selectedSample?.name ?? "还没有声音"
        accessibilityIdentifier = "voice.selection"
    }
    func presentChoices(from controller: UIViewController) {
        guard controller.presentedViewController == nil else { return }
        controller.view.endEditing(true)
        guard !VoiceLibraryStore.shared.samples.isEmpty else {
            controller.presentVoiceRecorder()
            return
        }
        let picker = VoicePickerViewController()
        picker.onCreate = { [weak controller] in controller?.presentVoiceRecorder() }
        picker.modalPresentationStyle = .pageSheet
        picker.sheetPresentationController?.detents = [.medium(), .large()]
        picker.sheetPresentationController?.prefersGrabberVisible = true
        controller.present(picker, animated: true)
    }
}

extension UIViewController {
    func presentVoiceRecorder() {
        guard presentedViewController == nil else { return }
        let recorder = RecordingViewController()
        recorder.modalPresentationStyle = .pageSheet
        recorder.sheetPresentationController?.detents = [.large()]
        recorder.sheetPresentationController?.prefersGrabberVisible = true
        present(recorder, animated: true)
    }
}

/// Decorative voice identity mark; it never represents measured microphone input.
final class VoiceIdentityView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = false
        heightAnchor.constraint(equalToConstant: 154).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        for radius: CGFloat in [72, 55, 38] {
            StudioTheme.accent.withAlphaComponent(0.12).setStroke()
            let circle = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            circle.lineWidth = 1
            circle.stroke()
        }
        for index in 0..<21 {
            let height = 12 + abs(sin(CGFloat(index) * 0.83) * cos(CGFloat(index) * 0.21)) * 48
            StudioTheme.accent.withAlphaComponent(0.8).setFill()
            UIBezierPath(roundedRect: CGRect(x: center.x - 52 + CGFloat(index) * 5, y: center.y - height / 2, width: 2.5, height: height), cornerRadius: 2).fill()
        }
    }
}
