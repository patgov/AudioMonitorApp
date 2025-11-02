import SwiftUI
import CoreAudio

struct AdvancedLogViewerView: View {
    let entries: [LogEntry]
    let logManager: any LogManagerProtocol

    @State private var selectedDevice = InputAudioDevice(id: 1, name: "Mock Mic", channelCount: 2)
    @State private var selectedLogLevel = "INFO"

    private var filteredEntries: [LogEntry] {
        entries.filter { $0.level == selectedLogLevel }
    }

    var body: some View {
        VStack(spacing: 16) {
            AdvancedLogViewerControlView(
                inputDevices: [selectedDevice],
                selectedDevice: $selectedDevice,
                selectedLogLevel: $selectedLogLevel
            )

            List(filteredEntries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.timestamp.formatted(date: .numeric, time: .standard))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(entry.message)
                        .font(.body)
                    HStack {
                        if let channel = entry.channel {
                            Text("Ch: \(channel)")
                        }
                        if let value = entry.value {
                            Text("Value: \(value, specifier: "%.1f") dB")
                        }
                    }
                    .font(.footnote)
                    .foregroundColor(.gray)
                }
                .padding(.vertical, 4)
            }

            Text("Current Input: \(logManager.latestStats.inputName)")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

    //struct LogEntryView: View {
    //   public let entry: AudioLogEntry
    //    let backgroundColor = Color.gray.opacity(0.12)
    //    var body: some View {
    //        let timestamp = entry.timestamp.formatted(date: .numeric, time: .standard)
    //        let value = String(format: "%.2f", entry.value)
    //
    //        return VStack(alignment: .leading, spacing: 4) {
    //            Text(timestamp)
    //                .font(.caption2)
    //                .foregroundColor(.secondary)
    //
    //            Text("\(entry.level): \(entry.message)")
    //                .font(.body)
    //                .foregroundColor(entry.level == "ERROR" ? .red : (entry.level == "WARNING" ? .yellow : .primary))
    //
    //            Text("Source: \(entry.source) | Channel: \(entry.channel) | Value: \(value)")
    //                .font(.caption)
    //                .foregroundColor(.gray)
    //        }
    //        .padding(6)
    //        .background(RoundedRectangle(cornerRadius: 8).fill(backgroundColor))
    //    }
    //}

#Preview {
    let dummyEntries = [
        LogEntry(
            timestamp: Date(),
            level: "INFO",
            source: "Preview",
            message: "Audio started",
            channel: 0,
            value: -42.3,
            inputName: "Built-in Mic",
            inputID: 1
        ),
        LogEntry(
            timestamp: Date(),
            level: "WARNING",
            source: "Preview",
            message: "Silence detected",
            channel: 1,
            value: -80.0,
            inputName: "Built-in Mic",
            inputID: 1
        ),
        LogEntry(
            timestamp: Date(),
            level: "ERROR",
            source: "Preview",
            message: "Overmodulation",
            channel: 0,
            value: 2.5,
            inputName: "Built-in Mic",
            inputID: 1
        )
    ]

    AdvancedLogViewerView(
        entries: dummyEntries,
        logManager: PreviewSafeLogManager(latestStats: .preview)
    )
}





    //
    //#Preview("Advanced Log Viewer Preview") {
    //    let dummyAudioManager = AudioManager()
    //    let dummyLogManager = LogManager(audioManager: dummyAudioManager)
    //
    //    dummyLogManager.addWarning(message: "Preview warning", channel: 0, value: -72.0)
    //    dummyLogManager.addError(message: "Preview error", channel: 1, value: -1.5)
    //
    //    return AdvancedLogViewerView(logManager: dummyLogManager)
    //}
