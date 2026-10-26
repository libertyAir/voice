import Foundation

/// Presentation-only state. No audio is recorded, synthesized, or played by this session.
struct ReaderDemoSession {
    struct ResultSnapshot {
        let voiceID: UUID
        let voiceName: String
        let text: String
        let duration: TimeInterval
        var position: TimeInterval = 0
        var isPlaying = false
    }

    private(set) var result: ResultSnapshot?
    private(set) var generationProgress: Double = 0
    private var pendingResult: ResultSnapshot?
    private let generationDuration: TimeInterval = 1.8

    var isGenerating: Bool { pendingResult != nil }
    var needsTimer: Bool { isGenerating || result?.isPlaying == true }

    mutating func generate(text: String, voiceID: UUID, voiceName: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pause()
        generationProgress = 0
        pendingResult = ResultSnapshot(voiceID: voiceID, voiceName: voiceName, text: text,
                                       duration: max(3, min(90, Double(text.count) / 4)))
    }

    mutating func cancelGeneration() {
        pendingResult = nil
        generationProgress = 0
    }

    mutating func togglePlayback() {
        guard !isGenerating, var current = result else { return }
        if current.position >= current.duration { current.position = 0 }
        current.isPlaying.toggle()
        result = current
    }

    mutating func pause() { result?.isPlaying = false }

    mutating func seek(to position: TimeInterval) {
        guard var current = result, position.isFinite else { return }
        current.position = min(current.duration, max(0, position))
        if current.position >= current.duration { current.isPlaying = false }
        result = current
    }

    /// Returns true only when a new result becomes ready, never for playback ticks.
    @discardableResult
    mutating func advance(by elapsed: TimeInterval) -> Bool {
        guard elapsed.isFinite, elapsed > 0 else { return false }
        if let pendingResult {
            generationProgress = min(1, generationProgress + elapsed / generationDuration)
            guard generationProgress >= 1 else { return false }
            result = pendingResult
            self.pendingResult = nil
            return true
        }
        guard var current = result, current.isPlaying else { return false }
        current.position = min(current.duration, current.position + elapsed)
        if current.position >= current.duration { current.isPlaying = false }
        result = current
        return false
    }

    func isResultOutdated(text: String, selectedVoiceID: UUID?) -> Bool {
        guard let result else { return false }
        return result.text != text || result.voiceID != selectedVoiceID
    }
}
