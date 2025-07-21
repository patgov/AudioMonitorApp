    //
    //  DummyLogManager.swift
    //  AudioMonitorApp
    //
    //  Created by Pat Govan on 6/11/25.
    //

import Foundation
import Combine


@MainActor
final class DummyLogManager: LogManagerProtocol {

    func addWarning(message: String, channel: Int?, value: Float?) {

    }
    
    func addError(message: String, channel: Int?, value: Float?) {

    }
    



    init() {



    }

    var latestStats: AudioStats {
        .zero
    }

    var statsPublisher: AnyPublisher<AudioStats, Never> {
        Just(.zero).eraseToAnyPublisher()
    }

    func log(_ message: String) {
        print("📝 [DummyLogManager] log ignored: \(message)")
    }

    func addWarning(message: String, channel: Int, value: Float) {
        print("⚠️ [DummyLogManager] warning ignored: \(message) [ch:\(channel)]")
    }

    func addError(message: String, channel: Int, value: Float) {
        print("❌ [DummyLogManager] error ignored: \(message) [ch:\(channel)]")
    }

    func clear() {}

    func simulate(_ stats: AudioStats) {}

    func updateInputName(_ name: String, id: Int) {}

    func start() {}

    func stop() {}

    var isLoggingEnabled: Bool {
        return false
    }

    func update(stats: AudioStats) {}

    func addInfo(message: String, channel: Int?, value: Float?) {
        print("ℹ️ [DummyLogManager] info ignored: \(message) [ch:\(channel ?? -1)]")
    }

    func reset() {}

    func updateAudioManager(_ audioManager: any AudioManagerProtocol) {}

    var logEntries: [LogEntry] {
        return []
    }

    func exportLog() {}

    func applyFilter(_ level: LogLevel) {

    }

    var logLevelFilter: LogLevel {
        .info
    }
}
