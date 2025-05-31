import Foundation
import Combine
import OSLog

@MainActor
public final class LogManager: ObservableObject, LogManagerProtocol {
  //  private let logger = Logger.logManager

        // ✅ Required by LogManagerProtocol
    public  var latestStats: AudioStats = .zero

        // ✅ Optional published logs for SwiftUI
    @Published public private(set) var logEntries: [LogEntry] = []

    private var audioManager: (any AudioManagerProtocol)?
    private let logLimit = 1000

        // MARK: - Init

    public init(audioManager: (any AudioManagerProtocol)? = nil) {
        self.audioManager = audioManager
    }

        // MARK: - LogManagerProtocol Conformance

    public func update(stats: AudioStats) {
        self.latestStats = stats
    }

    public func addInfo(message: String, channel: Int?, value: Float?) {
        addEntry(level: "INFO", message: message, channel: channel, value: value)
    }

    public func addWarning(message: String, channel: Int?, value: Float?) {
        addEntry(level: "WARNING", message: message, channel: channel, value: value)
    }

    public func addError(message: String, channel: Int?, value: Float?) {
        addEntry(level: "ERROR", message: message, channel: channel, value: value)
    }

    public func reset() {
        logEntries.removeAll()
     //   logger.info("🧹 Log entries reset.")
    }

    public func updateAudioManager(_ audioManager: any AudioManagerProtocol) {
        self.audioManager = audioManager
    }

        // MARK: - Internal Logging

    private func addEntry(
        level: String,
        message: String,
        channel: Int? = nil,
        value: Float? = nil
    ) {
        let entry = LogEntry(
            level: level,
            source: "LogManager",
            message: message,
            channel: channel,
            value: value,
            inputName: latestStats.inputName,
            inputID: latestStats.inputID
        )

        logEntries.append(entry)

        if logEntries.count > logLimit {
            logEntries.removeFirst()
        }

   //     logConsole(entry)
    }

//    private func logConsole(_ entry: LogEntry) {
//        switch entry.level {
//            case "ERROR":
//        //     logger.error("❌ \(entry.message, privacy: .public)")
//            case "WARNING":
//         //       logger.warning("⚠️ \(entry.message, privacy: .public)")
//            default: break
//       //         logger.info("ℹ️ \(entry.message, privacy: .public)")
//        }
//    }
}
