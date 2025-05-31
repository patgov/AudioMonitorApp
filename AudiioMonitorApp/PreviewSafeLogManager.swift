import Foundation
import Combine
import OSLog


@MainActor
public final class PreviewSafeLogManager: LogManagerProtocol {
    public private(set) var latestStats: AudioStats

    public init(latestStats: AudioStats = .preview) {
        self.latestStats = latestStats
    }

    public func update(stats: AudioStats) {
        latestStats = stats
    }

    public func addInfo(message: String, channel: Int?, value: Float?) {
            // No-op for previews
    }

    public func addWarning(message: String, channel: Int?, value: Float?) {
            // No-op for previews
    }

    public func addError(message: String, channel: Int?, value: Float?) {
            // No-op for previews
    }

    public func reset() {
            // No-op
    }

    public func updateAudioManager(_ audioManager: any AudioManagerProtocol) {
            // No-op
    }
}

