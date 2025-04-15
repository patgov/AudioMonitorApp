import Foundation
import Combine

class LogManager: ObservableObject {
    weak var audioManager: AudioManager!

    var stats: AudioStats
    private(set) var entries: [LogEntry] = []
    private let writer = LogWriter()

    init(audioManager: AudioManager?) {
        self.audioManager = audioManager
        self.stats = AudioStats(from: Date())
    }

    func processLevel(_ value: Float, channel: Int, inputName: String, inputID: Int) {
        let now = Date()

        if value < -50.0 {
            stats.recordSilence(channel: channel, timestamp: now)
            log(event: .silence, value: value, channel: channel, timestamp: now, inputName: inputName, inputID: inputID)
        }

        if value > -2.0 {
            stats.recordOvermodulation(channel: channel, timestamp: now)
            log(event: .overmodulation, value: value, channel: channel, timestamp: now, inputName: inputName, inputID: inputID)
        }
    }

    private func log(event: LogEventType, value: Float, channel: Int, timestamp: Date, inputName: String, inputID: Int) {
        let entry = LogEntry(
            timestamp: timestamp,
            level: event.rawValue,
            source: "Channel \(channel)",
            message: "\(event.rawValue.capitalized) on channel \(channel)",
            channel: channel,
            value: value,
            inputName: inputName,
            inputID: inputID
        )

        DispatchQueue.main.async {
            self.entries.append(entry)
        }

        writer.write(entry)
    }

    // Use Task.detached is used to read logs on a background thread, preventing async sendability errors while preserving responsiveness
    func loadLogEntries() async -> [LogEntry] {
        await withCheckedContinuation { continuation in
            let writerCopy = writer
            Task.detached(priority: .background) {
                let logs = writerCopy.readStructuredLogs()
                continuation.resume(returning: logs)
            }
        }
    }

    func resetStats() {
        stats = AudioStats(from: Date())
    }
}
    // Preview extension
extension LogManager {
    static var previewInstance: LogManager {
        let processor = AudioProcessor()
        let dummyLogManager = LogManager(audioManager: nil)
        let dummyAudioManager = AudioManager(processor: processor, logManager: dummyLogManager)
        dummyLogManager.audioManager = dummyAudioManager

        dummyLogManager.stats = AudioStats(from: Date())
        return dummyLogManager
    }
}

enum LogEventType: String {
    case silence
    case overmodulation
}
