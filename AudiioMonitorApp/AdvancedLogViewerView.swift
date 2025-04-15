    //
    //  AdvancedLogViewerView.swift
    //  AudiioMonitorApp
    //
    //  Created by Pat Govan on 3/30/25.
    //


import SwiftUI
import UniformTypeIdentifiers

struct AdvancedLogViewerView: View {
    var entries: [LogEntry]
    var logManager: LogManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log Viewer")
                .font(.title)
                .bold()

            if entries.isEmpty {
                Text("No log entries available.")
                    .foregroundColor(.secondary)
            } else {
                List(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("[\(entry.level)] \(entry.message)")
                            .font(.body)
                        Text("Source: \(entry.source), Input: \(entry.inputName), Channel: \(entry.channel)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }


            }
        }
        .padding()
    }
}

#Preview {
    let processor = AudioProcessor()
    let placeholderLogManager = LogManager(audioManager: nil)
    let dummyAudioManager = AudioManager(processor: processor, logManager: placeholderLogManager)
    placeholderLogManager.audioManager = dummyAudioManager

    let dummyEntries = [
        LogEntry(
            timestamp: Date(),
            level: "INFO",
            source: "Test",
            message: "Test entry",
            channel: 0,
            value: 0.0,
            inputName: "PreviewMic",
            inputID: 123
        )
    ]

        // ✅ Return a View type directly
    return AdvancedLogViewerView(entries: dummyEntries, logManager: placeholderLogManager)
}

        // MARK: - Document type for export
    struct LogFileDocument: FileDocument {
        static var readableContentTypes: [UTType] { [.plainText] }
        var content: String

        init(content: String) {
            self.content = content
        }

        init(configuration: ReadConfiguration) throws {
            guard let data = configuration.file.regularFileContents,
                  let string = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            content = string
        }

        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
            let data = content.data(using: .utf8)!
            return FileWrapper(regularFileWithContents: data)
        }
    }



#Preview {
    let processor = AudioProcessor()

    let dummyLogManager = LogManager(audioManager: DummyAudioManager())

    let dummyEntries = [
        LogEntry(
            timestamp: Date(),
            level: "INFO",
            source: "Test",
            message: "This is a test log entry",
            channel: 0,
            value: 0.0,
            inputName: "MockMic",
            inputID: 42
        )
    ]

    AdvancedLogViewerView(entries: dummyEntries, logManager: dummyLogManager)
}

#Preview {
    let logManager = LogManager.previewInstance

    return LogLoaderPreviewView(logManager: logManager)
}

private struct LogLoaderPreviewView: View {
    @State private var entries: [LogEntry] = []
    let logManager: LogManager

    var body: some View {
        AdvancedLogViewerView(entries: entries, logManager: logManager)
            .task {
                self.entries = await logManager.loadLogEntries()
            }
    }
}

struct AdvancedLogViewerPreviewContainer: View {
    @State private var entries: [LogEntry] = []
    private let logManager = LogManager(audioManager: DummyAudioManager())

    var body: some View {
        AdvancedLogViewerView(entries: entries, logManager: logManager)
            .task {
                let logs = await logManager.loadLogEntries()
                self.entries = logs
            }
    }
}

#Preview {
    AdvancedLogViewerPreviewContainer()
}
