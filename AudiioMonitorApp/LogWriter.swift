import Foundation

    //struct LogEntry: Identifiable {
    //    let id = UUID()
    //    let timestamp: Date
    //    let level: String
    //    let source: String
    //    let message: String
    //}

import Foundation

    /// Struct to hold current session statistics
struct AudioStats {
    var silenceCount: [Int] = [0, 0]   // [Left, Right]
    var overmodulationCount: [Int] = [0, 0]
}

class LogWriter {
    private(set) var logFileURL: URL
    static let shared = LogWriter()
    init() {
        let filename = "AudioMonitorLog.txt"
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        logFileURL = directory.appendingPathComponent(filename)
        
        ensureLogFile()
    }
    
    func write(_ message: String, tag: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(tag)] \(message)\n"
        append(line: line)
    }
    
    private func append(line: String) {
        guard let data = line.data(using: .utf8) else { return }
        
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: logFileURL)
        }
    }

    func readStructuredLogs() -> [LogEntry] {
        guard let data = try? String(contentsOf: logFileURL, encoding: .utf8),
        !data.isEmpty else { return [] }

        let lines = data.components(separatedBy: .newlines)
        let formatter = ISO8601DateFormatter()

        return lines.compactMap { line in
            let pattern = #"\[(.*?)\] \[(.*?)\] (.*?): (.*)"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  match.numberOfRanges == 5 else {
                return nil
            }

            let dateStr = String(line[Range(match.range(at: 1), in: line)!])
            let level = String(line[Range(match.range(at: 2), in: line)!])
            let source = String(line[Range(match.range(at: 3), in: line)!])
            let message = String(line[Range(match.range(at: 4), in: line)!])

            let timestamp = formatter.date(from: dateStr) ?? Date()
            return LogEntry(timestamp: timestamp, level: level, source: source, message: message)
        }
    }

    @discardableResult
    func ensureLogFile() -> Bool {
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            return FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        return true
    }
}

    /// Singleton log manager to handle stats, logs, and UI updates
class LogManager: ObservableObject {
    static let shared = LogManager()
    
    private let logWriter = LogWriter()
    @Published private(set) var stats = AudioStats()
    
        /// Optional callback to deliver events to UI
    var onLevelEvent: ((_ channel: Int, _ dB: Float, _ event: LevelEvent?) -> Void)?
    
    enum LevelEvent: String {
        case silence
        case overmodulation
    }
    
    init() {

        
    }

    func processLevel(_ dB: Float, channel: Int) {
        let tag = channel == 0 ? "L" : "R"
        
        var event: LevelEvent? = nil
        
        if dB < -60 {
            stats.silenceCount[channel] += 1
            logWriter.write("🔇 Silence on channel \(tag)", tag: "SILENCE")
            event = .silence
        } else if dB > 0 {
            stats.overmodulationCount[channel] += 1
            logWriter.write("🚨 Overmodulation on channel \(tag)", tag: "OVERMOD")
            event = .overmodulation
        }
        
        onLevelEvent?(channel, dB, event)
    }
    
    func resetStats() {
        stats = AudioStats()
    }
}

extension LogWriter {
        /// Returns the full log contents as a string
    func exportLog() -> String {
        do {
            return try String(contentsOf: logFileURL, encoding: .utf8)
        } catch {
            print("❌ Failed to export log: \(error)")
            return ""
        }
    }
    
        /// Moves the current log to an archive and resets the file
    func archiveAndResetLog() {
        let timestamp = Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "-")
        let archiveURL = logFileURL.deletingLastPathComponent()
            .appendingPathComponent("log-\(timestamp).txt")
        
        do {
            try FileManager.default.moveItem(at: logFileURL, to: archiveURL)
            print("📦 Archived log to \(archiveURL.lastPathComponent)")
            _ = ensureLogFile()
        } catch {
            print("❌ Failed to archive log: \(error)")
        }
    }
}
