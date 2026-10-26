import AVFoundation
import UIKit

struct RecordedClip {
    let url: URL
    let duration: TimeInterval
}

enum VoiceAudioError: LocalizedError {
    case microphoneDenied
    case busy
    case cancelled
    case unavailable
    case emptyRecording

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: return "麦克风权限未开启，请到系统设置中允许 Voices 使用麦克风。"
        case .busy: return "录音正在进行，请先结束当前录音。"
        case .cancelled: return "录音已取消。"
        case .unavailable: return "暂时无法使用音频设备，请检查麦克风或耳机后重试。"
        case .emptyRecording: return "没有获得可播放的录音，请再试一次。"
        }
    }
}

@MainActor
final class AudioRecorderService: NSObject {
    private(set) var isRecording = false
    private(set) var isRequestingPermission = false
    var onUpdate: ((TimeInterval, Float) -> Void)?
    var onError: ((String) -> Void)?
    var onInterruption: (() -> Void)?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var requestID: UUID?
    private var startCompletion: ((Result<Void, Error>) -> Void)?
    private var retainedClip: RecordedClip?

    override init() {
        super.init()
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  value == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor [weak self] in self?.handleInterruption() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleInterruption() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleInterruption() }
        })
    }

    deinit {
        timer?.invalidate()
        recorder?.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        guard !isRecording, !isRequestingPermission else {
            completion(.failure(VoiceAudioError.busy))
            return
        }
        guard retainedClip == nil else {
            completion(.failure(VoiceAudioError.busy))
            return
        }
        let id = UUID()
        requestID = id
        startCompletion = completion
        isRequestingPermission = true
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            resolvePermission(granted: true, id: id)
        case .denied:
            resolvePermission(granted: false, id: id)
        case .undetermined:
            session.requestRecordPermission { [weak self] granted in
                Task { @MainActor [weak self] in self?.resolvePermission(granted: granted, id: id) }
            }
        @unknown default:
            resolvePermission(granted: false, id: id)
        }
    }

    func stop() -> RecordedClip? {
        cancelPendingStart()
        if let recorder {
            self.recorder = nil
            isRecording = false
            timer?.invalidate()
            timer = nil
            recorder.delegate = nil
            let url = recorder.url
            recorder.stop()
            deactivateSession()
            do {
                let audio = try AVAudioPlayer(contentsOf: url)
                guard audio.duration.isFinite, audio.duration > 0 else {
                    throw VoiceAudioError.emptyRecording
                }
                return RecordedClip(url: url, duration: audio.duration)
            } catch {
                try? FileManager.default.removeItem(at: url)
                onError?(VoiceAudioError.emptyRecording.localizedDescription)
                return nil
            }
        }
        let clip = retainedClip
        retainedClip = nil
        return clip
    }

    func discard() {
        if let clip = stop() { try? FileManager.default.removeItem(at: clip.url) }
        if let retainedClip { try? FileManager.default.removeItem(at: retainedClip.url) }
        retainedClip = nil
    }

    private func resolvePermission(granted: Bool, id: UUID) {
        guard requestID == id else { return }
        requestID = nil
        isRequestingPermission = false
        let completion = startCompletion
        startCompletion = nil
        guard granted else {
            completion?(.failure(VoiceAudioError.microphoneDenied))
            return
        }
        guard UIApplication.shared.applicationState != .background else {
            completion?(.failure(VoiceAudioError.cancelled))
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voices-recording-\(UUID().uuidString).m4a")
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.delegate = self
            guard recorder.prepareToRecord(), recorder.record() else {
                throw VoiceAudioError.unavailable
            }
            self.recorder = recorder
            isRecording = true
            startMetering()
            completion?(.success(()))
        } catch {
            try? FileManager.default.removeItem(at: url)
            deactivateSession()
            completion?(.failure(error))
        }
    }

    private func startMetering() {
        onUpdate?(0, 0)
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let recorder = self.recorder, self.isRecording else { return }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)
                let level = min(1, max(0, pow(10, power / 30)))
                self.onUpdate?(recorder.currentTime, level)
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelPendingStart() {
        guard isRequestingPermission else { return }
        requestID = nil
        isRequestingPermission = false
        let completion = startCompletion
        startCompletion = nil
        completion?(.failure(VoiceAudioError.cancelled))
    }

    private func handleInterruption() {
        guard isRecording || isRequestingPermission else { return }
        cancelPendingStart()
        // The screen gets first chance to save or present the interrupted recording.
        onInterruption?()
        if isRecording { retainedClip = stop() }
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension AudioRecorderService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let identifier = ObjectIdentifier(recorder)
        let message = error?.localizedDescription ?? VoiceAudioError.unavailable.localizedDescription
        Task { @MainActor [weak self] in
            guard let self, let current = self.recorder,
                  ObjectIdentifier(current) == identifier else { return }
            self.handleInterruption()
            self.onError?(message)
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let identifier = ObjectIdentifier(recorder)
        Task { @MainActor [weak self] in
            guard let self, let current = self.recorder,
                  ObjectIdentifier(current) == identifier else { return }
            self.handleInterruption()
            if !flag { self.onError?(VoiceAudioError.unavailable.localizedDescription) }
        }
    }
}
