import Foundation
import Combine

@MainActor
final class AudioProcessor {
    // Floor threshold for displaying decibel levels (in dBFS). Values lower than this are clamped.
    private let dBFloorThreshold: Float = -80.0

    // Current clamped levels
    public private(set) var currentLeftLevel: Float = -80.0
    public private(set) var currentRightLevel: Float = -80.0

    // Stream of raw stats
    let audioStatsStream = PassthroughSubject<AudioStats, Never>()

    // Optional log manager reference
    private var logManager: (any LogManagerProtocol)?

    // Allow AudioManager (or others) to provide a logger
    func updateLogManager(_ logManager: some LogManagerProtocol) {
        self.logManager = logManager
    }

    public func ingest(leftDB: Float, rightDB: Float, inputName: String, inputID: Int) {
        let displayLeftDB  = max(leftDB,  dBFloorThreshold)
        let displayRightDB = max(rightDB, dBFloorThreshold)

        self.currentLeftLevel  = displayLeftDB
        self.currentRightLevel = displayRightDB

        let stats = AudioStats(
            left: leftDB,
            right: rightDB,
            inputName: inputName,
            inputID: inputID
        )

        // Publish stats on main actor
        self.audioStatsStream.send(stats)

        // Forward to log manager if available
        self.logManager?.update(stats: stats)
    }
}
