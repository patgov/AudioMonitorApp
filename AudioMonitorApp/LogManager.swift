// NOTE: This file uses Combine publishers and properties accessed by SwiftUI. All mutations to @Published properties (logEntries, latestStats) and calls to @MainActor methods must be performed on the main actor to comply with Swift 6 concurrency rules. If mutation might occur off the main thread, dispatch or use Task {@MainActor in ...} for safety.
//
// All Combine subscriptions and publishing related to logs should remain on the main actor unless otherwise documented.

import Foundation
import Combine
import OSLog
import SwiftUI

@MainActor
final class LogManager: ObservableObject, LogManagerProtocol {
    
    private let logger = Logger(subsystem: "com.audiomonitor.app", category: "LogManager")
    
        // Protocol
    var latestStats: AudioStats = .zero
    
        // Optional published logs for UI
    @Published private(set) var logEntries: [LogEntry] = []
    
    private var audioManager: (any AudioManagerProtocol)?
    private let logLimit = 1000
    private var isMonoInput = false
    
    init(audioManager: (any AudioManagerProtocol)? = nil) {
        if let manager = audioManager { updateAudioManager(manager) }
        logger.info("✅ LogManager initialized with audioManager: \(String(describing: audioManager))")
    }
    
        // MARK: - LogManagerProtocol
    
    func update(stats: AudioStats) {
        if isMonoInput {
            latestStats = AudioStats(
                left: stats.left,
                right: stats.left,
                inputName: stats.inputName,
                inputID: stats.inputID
            )
        } else {
            latestStats = stats
        }
    }
    
    func addInfo(message: String, channel: Int?, value: Float?)   { addEntry(level: "INFO",    message: message, channel: channel, value: value) }
    func addWarning(message: String, channel: Int?, value: Float?) { addEntry(level: "WARNING", message: message, channel: channel, value: value) }
    func addError(message: String, channel: Int?, value: Float?)   { addEntry(level: "ERROR",   message: message, channel: channel, value: value) }
    
    func reset() { logEntries.removeAll() }
    
    func updateAudioManager(_ audioManager: any AudioManagerProtocol) {
        self.audioManager = audioManager
        self.isMonoInput = (audioManager.leftLevel == audioManager.rightLevel)
    }
    
        // MARK: - Internal logging
    private func addEntry(level: String, message: String, channel: Int? = nil, value: Float? = nil) {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            source: "LogManager",
            message: message,
            channel: channel,
            value: value,
            inputName: latestStats.inputName,
            inputID: latestStats.inputID
        )
        logEntries.append(entry)
        if logEntries.count > logLimit { logEntries.removeFirst() }
    }
}

    // Optional internal mock
@MainActor
final class MockLogManager: ObservableObject, LogManagerProtocol {
    var latestStats: AudioStats = .preview
    @Published private(set) var logEntries: [LogEntry] = [
        LogEntry(timestamp: Date(), level: "INFO", source: "Preview", message: "Sample log",
                 channel: 1, value: -12.3, inputName: "PreviewMic", inputID: 123)
    ]
    
    func update(stats: AudioStats) { latestStats = stats }
    func addInfo(message: String, channel: Int?, value: Float?) {}
    func addWarning(message: String, channel: Int?, value: Float?) {}
    func addError(message: String, channel: Int?, value: Float?) {}
    func reset() {}
    func updateAudioManager(_ audioManager: any AudioManagerProtocol) {}
}


