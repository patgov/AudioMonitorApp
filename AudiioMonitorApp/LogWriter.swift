import Foundation

    /// Struct to hold current session statistics
struct AudioStats {
    var silenceCount: [Int] = [0, 0]   // [Left, Right]
    var overmodulationCount: [Int] = [0, 0]
}

final class LogWriter:  @unchecked Sendable {

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
        print("📄 Writing to log file: \(line)")
    }

    private func append(line: String) {
        print("📤 Writing log line: \(line)")
        let lineWithNewline = line + "\n"  // ✅ Add newline so each log entry is a new line
        guard let data = lineWithNewline.data(using: .utf8) else { return }

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

        var entries: [LogEntry] = []

        let pattern = #"\[(.*?)\] \[(.*?)\] (.*)"#
        let regex = try? NSRegularExpression(pattern: pattern)

        for line in lines {
            guard let regex = regex else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, options: [], range: range),
                  match.numberOfRanges == 4 else { continue }

            let dateStr = String(line[Range(match.range(at: 1), in: line)!])
            let level = String(line[Range(match.range(at: 2), in: line)!])
            let message = String(line[Range(match.range(at: 3), in: line)!])
            let timestamp = formatter.date(from: dateStr) ?? Date()

            let entry = LogEntry(
                timestamp: timestamp,
                level: level,
                source: "Unknown", message: message,
                channel: -1,
                value: -1.0
            )

            entries.append(entry)
        }

        return entries
    }


    func readStructuredLogsAsync() async -> [LogEntry] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                let logs = self.readStructuredLogs()
                continuation.resume(returning: logs)
            }
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


extension AudioStats {
    var silenceCountLeft: Int {
        get { silenceCount.indices.contains(0) ? silenceCount[0] : 0 }
        set { if silenceCount.indices.contains(0) { silenceCount[0] = newValue } }
    }
    
    var silenceCountRight: Int {
        get { silenceCount.indices.contains(1) ? silenceCount[1] : 0 }
        set { if silenceCount.indices.contains(1) { silenceCount[1] = newValue } }
    }
    
    var overmodulationCountLeft: Int {
        get { overmodulationCount.indices.contains(0) ? overmodulationCount[0] : 0 }
        set { if overmodulationCount.indices.contains(0) { overmodulationCount[0] = newValue } }
    }
    
    var overmodulationCountRight: Int {
        get { overmodulationCount.indices.contains(1) ? overmodulationCount[1] : 0 }
        set { if overmodulationCount.indices.contains(1) { overmodulationCount[1] = newValue } }
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
