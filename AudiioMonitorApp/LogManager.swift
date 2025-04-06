import Foundation
import Combine

@MainActor
class LogManager: ObservableObject {
    private(set) var logWriter = LogWriter()
    static let shared = LogManager()
    
    @Published private(set) var entries: [LogEntry] = []
    private let writer = LogWriter()
    @Published var stats = AudioStats()
    
    
    func processLevel(_ level: Float, channel: Int) {
        let now = Date()
        
        if level < -50 {
            log(event: .silence, value: level, channel: channel, timestamp: now)
        } else if level > -2 {
            log(event: .overmodulated, value: level, channel: channel, timestamp: now)
        }
    }
    
    func resetStats() {
        stats = AudioStats() // resets all values to 0
    }
    
    private func log(event: LogEventType, value: Float, channel: Int, timestamp: Date) {
        let entry = LogEntry(
            timestamp: timestamp,
            level: event.rawValue,
            source: "Channel \(String(channel))",
            message: "\(value)",
            channel: channel,
            value: value  // ✅ Corrected: Pass as Float
        )
        DispatchQueue.main.async {
            self.entries.append(entry)
        }
        writer.write(entry.message, tag: "Log")
    }
    
    func clearLogs() {
        entries.removeAll()
            // writer.clearLogFile() // Ensure this method exists in LogWriter or comment this line out.
    }
    
    func exportLog() -> String {
        return entries.map { "\($0.timestamp): \($0.message)" }.joined(separator: "\n")
    }
    
    struct AudioStats {
        var silenceCountLeft: Int = 0
        var silenceCountRight: Int = 0
        var overmodulationCountLeft: Int = 0
        var overmodulationCountRight: Int = 0
    }
    
    @MainActor
    func loadLogEntries() async -> [LogEntry] {
            // Temporarily prints results in logManager
        let logs = self.logWriter.readStructuredLogs()
        print("📜 Loaded \(logs.count) entries")
        
        return logWriter.readStructuredLogs()
        
    }
}


enum LogEventType: String {
    case silence = "Silence"
    case overmodulated = "Overmodulation"
}
