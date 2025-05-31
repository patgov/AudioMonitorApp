
import Foundation
import OSLog

enum LogSystem {
    static func reportStartupStatus() {
        let bundle = Bundle.main
        let bundleID = bundle.bundleIdentifier ?? "nil"
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"

        Logger.preview.info("🧭 Subsystem resolved to: \(bundleID, privacy: .public)")
        Logger.preview.info("📦 App Version: \(version, privacy: .public) (\(build, privacy: .public))")

        Logger.audioManager.info("✅ Logger ready: AudioManager")
        Logger.logManager.info("✅ Logger ready: LogManager")
        Logger.audioMonitorViewModel.info("✅ Logger ready: AudioMonitorViewModel")
        Logger.audioProcessor.info("✅ Logger ready: AudioProcessor")
        Logger.diagnostics.info("✅ Logger ready: Diagnostics")
    }

    static func diagnosticsText() -> String {
        let bundle = Bundle.main
        let bundleID = bundle.bundleIdentifier ?? "nil"
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let environment = isDebug ? "DEBUG" : "RELEASE"

        return """
    🔍 Diagnostics:
    • Subsystem: \(bundleID)
    • App Version: \(version) (\(build))
    • Environment: \(environment)
    • Loggers: AudioManager, LogManager, AudioMonitorViewModel, AudioProcessor, Diagnostics
    """
    }

    private static var isDebug: Bool {
#if DEBUG
        return true
#else
        return false
#endif
    }

}
