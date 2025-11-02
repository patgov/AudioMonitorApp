import Foundation
import Combine
import OSLog


@MainActor
final class PreviewSafeLogManager: LogManagerProtocol {
    private(set) var latestStats: AudioStats
    
    init(latestStats: AudioStats = .preview) {
        self.latestStats = latestStats
    }
    
    func update(stats: AudioStats) {
        latestStats = stats
    }
    
    func addInfo(message: String, channel: Int?, value: Float?) { }
    func addWarning(message: String, channel: Int?, value: Float?) { }
    func addError(message: String, channel: Int?, value: Float?) { }
    func reset() { }
    func updateAudioManager(_ audioManager: any AudioManagerProtocol) { }
}
