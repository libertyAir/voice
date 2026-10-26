import AVFoundation
import UIKit

@MainActor
final class AudioPlaybackService: NSObject {
    private(set) var isPlaying = false
    private(set) var isPaused = false
    var onUpdate: ((TimeInterval, TimeInterval, Float) -> Void)?
    var onFinish: (() -> Void)?
    var onError: ((String) -> Void)?

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var hasActiveSession = false

    override init() {
        super.init()
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  value == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor [weak self] in self?.finishAfterInterruption() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.finishAfterInterruption() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  value == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor [weak self] in self?.finishAfterInterruption() }
        })
    }

    deinit {
        timer?.invalidate()
        player?.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func play(url: URL) throws {
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            hasActiveSession = true
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.isMeteringEnabled = true
            guard player.prepareToPlay(), player.play() else { throw VoiceAudioError.unavailable }
            self.player = player
            isPlaying = true
            isPaused = false
            onUpdate?(0, player.duration, 0)
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let player = self.player, self.isPlaying else { return }
                    player.updateMeters()
                    let level = min(1, max(0, pow(10, player.averagePower(forChannel: 0) / 30)))
                    self.onUpdate?(player.currentTime, player.duration, level)
                }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        player?.delegate = nil
        player?.stop()
        player = nil
        isPlaying = false
        isPaused = false
        timer?.invalidate()
        timer = nil
        if hasActiveSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            hasActiveSession = false
        }
    }

    func pause() {
        guard isPlaying, let player else { return }
        player.pause()
        isPlaying = false
        isPaused = true
        onUpdate?(player.currentTime, player.duration, 0)
        if hasActiveSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            hasActiveSession = false
        }
    }

    func resume() throws {
        guard isPaused, let player else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            hasActiveSession = true
            guard player.play() else { throw VoiceAudioError.unavailable }
            isPlaying = true
            isPaused = false
        } catch {
            stop()
            throw error
        }
    }

    private func finishAfterInterruption() {
        guard isPlaying || isPaused else { return }
        stop()
        onFinish?()
    }
}

extension AudioPlaybackService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identifier = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.player,
                  ObjectIdentifier(current) == identifier else { return }
            self.stop()
            if !flag { self.onError?(VoiceAudioError.unavailable.localizedDescription) }
            self.onFinish?()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let identifier = ObjectIdentifier(player)
        let message = error?.localizedDescription ?? "录音播放失败，请检查音频文件。"
        Task { @MainActor [weak self] in
            guard let self, let current = self.player,
                  ObjectIdentifier(current) == identifier else { return }
            self.stop()
            self.onError?(message)
            self.onFinish?()
        }
    }
}
