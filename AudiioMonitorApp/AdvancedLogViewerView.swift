    //
    //  AdvancedLogViewerView.swift
    //  AudiioMonitorApp
    //
    //  Created by Pat Govan on 3/30/25.
    //

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct AdvancedLogViewerView: View {
    var entries: [LogEntry]

    var body: some View {
        if entries.isEmpty {
            Text("No log entries available.")
                .foregroundColor(.secondary)
                .padding()
        } else {
            List(entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text("[\(entry.level)] \(entry.source)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text(entry.message)
                        .font(.body)
                }
            }
        }
    }
}

#Preview {
    AdvancedLogViewerView(entries: [
        LogEntry(timestamp: Date(), level: "INFO", source: "Test", message: "This is a test log.", channel: 0, value: 0.0)
    ])
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
