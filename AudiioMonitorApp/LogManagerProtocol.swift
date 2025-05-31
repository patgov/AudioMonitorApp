import Foundation
import Combine


@MainActor
public protocol LogManagerProtocol: AnyObject {
        /// The latest audio statistics, updated in real-time.
    var latestStats: AudioStats { get }

        /// Called by the audio processor to update the current statistics.
    func update(stats: AudioStats)

        /// Records an informational log message.
    func addInfo(message: String, channel: Int?, value: Float?)

        /// Records a warning log message (e.g. silence detected).
    func addWarning(message: String, channel: Int?, value: Float?)

        /// Records an error log message (e.g. overmodulation).
    func addError(message: String, channel: Int?, value: Float?)

        /// Clears all stored log entries.
    func reset()

        /// Optionally updates the associated audio manager (for stats tagging).
    func updateAudioManager(_ audioManager: any AudioManagerProtocol)
}



/*
 All protocol-conforming implementations (e.g., PreviewSafeLogManager, LogManager, etc.) must also follow this access control chain—otherwise they’ll fail to conform in Swift 6.
 inspect your AudioLogEntry.swift and AudioStats.swift files to apply public visibility to all necessary types and properties?
 */
