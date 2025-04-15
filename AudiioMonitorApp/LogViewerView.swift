import SwiftUI

struct LogViewerView: View {

    @EnvironmentObject var logManager: LogManager
    @State private var entries: [LogEntry] = []
    @State private var logs: String = ""

    
    var body: some View {
        VStack {
            Text("Log Entries")
                .font(.title2)
                .padding()
            
            if entries.isEmpty {
                Text("No log entries available.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("[\(entry.timestamp.formatted())] [\(entry.level.uppercased())] [\(entry.source)]")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(entry.message)
                                    .font(.body)
                            }
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                }
            }
            
            Spacer()
            
            Button("Close") {
                NSApp.keyWindow?.close()
            }
            .padding(.top, 10)
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            Task {
                self.entries = await logManager.loadLogEntries()
            }
        }
    }
}

#Preview {
    LogViewerView()
}
