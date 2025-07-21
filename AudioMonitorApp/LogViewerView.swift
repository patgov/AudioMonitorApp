import SwiftUI

struct LogViewerView: View {
    @ObservedObject var logManager: LogManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log Viewer")
                .font(.title2)
                .padding(.bottom, 4)

            if logManager.logEntries.isEmpty {
                Text("No log entries available.")
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(logManager.logEntries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.timestamp.formatted(date: .numeric, time: .standard))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Text(entry.message)
                                    .font(.body)

                                Text("Level: \(entry.level) • Source: \(entry.source) • Channel: \(String(describing: entry.channel))")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15)))
                        }
                    }
                }
            }
        }
        .padding()
    }
}

#Preview {
    let dummyLogManager = LogManager(audioManager: AudioManager())
   // dummyLogManager.addInfo(message: "Preview log message", channel: 0, value: -42.5)
    LogViewerView(logManager: dummyLogManager)
}
