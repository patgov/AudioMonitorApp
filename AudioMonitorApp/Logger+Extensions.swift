
import OSLog
import Foundation

extension Logger {
        // Dynamically fetches the app's bundle identifier; falls back if nil
    private static let subsystem = Bundle.main.bundleIdentifier ?? "us.govango.AudiioMonitorApp"

    public static let audioManager = Logger(subsystem: subsystem, category: "AudioManager")
    public static let logManager = Logger(subsystem: subsystem, category: "LogManager")
    public static let audioMonitorViewModel = Logger(subsystem: subsystem, category: "AudioMonitorViewModel")
    public static let audioProcessor = Logger(subsystem: subsystem, category: "AudioProcessor")
    public static let diagnostics = Logger(subsystem: subsystem, category: "Diagnostics")
    public static let preview = Logger(subsystem: subsystem, category: "Preview")
}

    // Logger.audioProcessor.debug("Buffer processed")
    // Logger.logManager.warning("Silence detected")
