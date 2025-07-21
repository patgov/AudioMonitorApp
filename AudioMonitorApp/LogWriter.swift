import Foundation

final class LogWriter: @unchecked Sendable {
    private let logFileName = "AudioMonitorLog.txt"

    private var logFileURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent(logFileName)
    }

    func write(_ entry: LogEntry) {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: entry.timestamp)
        let value = entry.value ?? 0.0
        let line = "[\(timestamp)] [\(entry.level)] \(entry.source): \(entry.message) | Channel: \(String(describing: entry.channel)) | Value: \(String(format: "%.2f", value)) | Input: \(entry.inputName) [\(entry.inputID)]\n"
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

    func clearLogFile() {
        try? FileManager.default.removeItem(at: logFileURL)
    }

    func readStructuredLogs() -> [LogEntry] {
        guard let content = try? String(contentsOf: logFileURL, encoding: .utf8), !content.isEmpty
        else {
            return []
        }

        let formatter = ISO8601DateFormatter()
        var entries: [LogEntry] = []

        let lines = content.components(separatedBy: .newlines)

        let pattern = #"\[(.*?)\] \[(.*?)\] (.*?): (.*?) \| Channel: (\d+) \| Value: ([\d.-]+) \| Input: (.*?) \[(\d+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, options: [], range: range),
                  match.numberOfRanges == 9 else {
                continue
            }

            let timestampStr = String(line[Range(match.range(at: 1), in: line)!])
            let level = String(line[Range(match.range(at: 2), in: line)!])
            let source = String(line[Range(match.range(at: 3), in: line)!])
            let message = String(line[Range(match.range(at: 4), in: line)!])
            let channelStr = String(line[Range(match.range(at: 5), in: line)!])
            let valueStr = String(line[Range(match.range(at: 6), in: line)!])
            let inputName = String(line[Range(match.range(at: 7), in: line)!])
            let inputIDStr = String(line[Range(match.range(at: 8), in: line)!])

            guard let timestamp = formatter.date(from: timestampStr),
                  let channel = Int(channelStr),
                  let value = Float(valueStr),
                  let inputID = Int(inputIDStr) else { continue }

            let entry = LogEntry(
                timestamp: timestamp,
                level: level,
                source: source,
                message: message,
                channel: channel,
                value: value,
                inputName: inputName,
                inputID: inputID
            )

            entries.append(entry)
        }

        return entries
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
                //   _ = ensureLogFile()
        } catch {
            print("❌ Failed to archive log: \(error)")
        }
    }
}
