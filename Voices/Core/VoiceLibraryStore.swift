import Foundation

struct VoiceSample: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let fileName: String
    let createdAt: Date
    let duration: TimeInterval
}

extension Notification.Name {
    static let voiceLibraryDidChange = Notification.Name("voices.voiceLibraryDidChange")
}

enum VoiceStorageError: LocalizedError {
    case emptyName
    case invalidRecording
    case sampleNotFound
    case unreadableLibrary

    var errorDescription: String? {
        switch self {
        case .emptyName: return "请为这段声音填写名称。"
        case .invalidRecording: return "这段录音无法保存，请重新录制。"
        case .sampleNotFound: return "这段声音已不存在，请重新选择。"
        case .unreadableLibrary: return "声音库暂时无法读取。为保护已有录音，暂未保存更改。"
        }
    }
}

@MainActor
final class VoiceLibraryStore {
    static let shared = VoiceLibraryStore()

    private(set) var samples: [VoiceSample] = []
    private(set) var selectedID: UUID?
    private(set) var loadError: String?

    var selectedSample: VoiceSample? {
        samples.first { $0.id == selectedID }
    }

    private struct Library: Codable {
        let samples: [VoiceSample]
        let selectedID: UUID?
    }

    private let fileManager: FileManager
    private let directory: URL
    private var metadataURL: URL { directory.appendingPathComponent("library.json") }
    private var canWrite = true

    // The directory can be supplied by a focused persistence test without touching app data.
    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory ?? fileManager.urls(for: .applicationSupportDirectory,
                                                       in: .userDomainMask)[0]
            .appendingPathComponent("VoiceLibrary", isDirectory: true)
        load()
    }

    func fileURL(for sample: VoiceSample) -> URL {
        // Use the ID rather than trusting a path decoded from metadata.
        directory.appendingPathComponent("\(sample.id.uuidString).m4a")
    }

    @discardableResult
    func addRecording(from url: URL, name: String, duration: TimeInterval) throws -> VoiceSample {
        try ensureWritable()
        let cleanName = try validatedName(name)
        guard duration.isFinite, duration > 0,
              url.isFileURL,
              fileManager.fileExists(atPath: url.path),
              (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 else {
            throw VoiceStorageError.invalidRecording
        }
        let id = UUID()
        let sample = VoiceSample(id: id, name: cleanName, fileName: "\(id.uuidString).m4a",
                                 createdAt: Date(), duration: duration)
        let destination = fileURL(for: sample)
        try fileManager.copyItem(at: url, to: destination)
        let updated = [sample] + samples
        do {
            try persist(samples: updated, selectedID: id)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
        samples = updated
        selectedID = id
        loadError = nil
        // Only consume a temporary recording after the library has been committed.
        if url.standardizedFileURL.path.hasPrefix(fileManager.temporaryDirectory.standardizedFileURL.path) {
            try? fileManager.removeItem(at: url)
        }
        notifyChange()
        return sample
    }

    func rename(_ sample: VoiceSample, to name: String) throws {
        try ensureWritable()
        guard let index = samples.firstIndex(where: { $0.id == sample.id }) else {
            throw VoiceStorageError.sampleNotFound
        }
        var updated = samples
        updated[index].name = try validatedName(name)
        try persist(samples: updated, selectedID: selectedID)
        samples = updated
        loadError = nil
        notifyChange()
    }

    func delete(_ sample: VoiceSample) throws {
        try ensureWritable()
        guard samples.contains(where: { $0.id == sample.id }) else {
            throw VoiceStorageError.sampleNotFound
        }
        let updated = samples.filter { $0.id != sample.id }
        let nextSelection = selectedID == sample.id ? updated.first?.id : selectedID
        // Persist first: a failed metadata write must never remove a user's recording.
        try persist(samples: updated, selectedID: nextSelection)
        do {
            let url = fileURL(for: sample)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        } catch {
            do {
                try persist(samples: samples, selectedID: selectedID)
            } catch {
                canWrite = false
                loadError = "声音库保存失败，请重新启动 App 后检查录音。"
            }
            throw error
        }
        samples = updated
        selectedID = nextSelection
        loadError = nil
        notifyChange()
    }

    func select(_ sample: VoiceSample?) {
        guard canWrite else { return }
        if let sample, !samples.contains(where: { $0.id == sample.id }) { return }
        let nextID = sample?.id
        guard nextID != selectedID else { return }
        do {
            try persist(samples: samples, selectedID: nextID)
            selectedID = nextID
            loadError = nil
            notifyChange()
        } catch {
            loadError = "声音选择未能保存：\(error.localizedDescription)"
            notifyChange()
        }
    }

    private func load() {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            guard fileManager.fileExists(atPath: metadataURL.path) else { return }
            let library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: metadataURL))
            guard Set(library.samples.map(\.id)).count == library.samples.count,
                  library.samples.allSatisfy({
                      $0.fileName == "\($0.id.uuidString).m4a" && $0.duration.isFinite && $0.duration > 0
                  }) else {
                throw VoiceStorageError.unreadableLibrary
            }
            samples = library.samples
            selectedID = samples.contains(where: { $0.id == library.selectedID })
                ? library.selectedID : samples.first?.id
        } catch {
            canWrite = false
            loadError = "暂时无法读取声音库，已有文件会保留。\n\(error.localizedDescription)"
        }
    }

    private func ensureWritable() throws {
        guard canWrite else { throw VoiceStorageError.unreadableLibrary }
    }

    private func validatedName(_ name: String) throws -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw VoiceStorageError.emptyName }
        return value
    }

    private func persist(samples: [VoiceSample], selectedID: UUID?) throws {
        let data = try JSONEncoder().encode(Library(samples: samples, selectedID: selectedID))
        try data.write(to: metadataURL, options: .atomic)
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .voiceLibraryDidChange, object: self)
    }
}
