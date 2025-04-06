    //
    //  AudiioMonitorAppApp.swift
    //  AudiioMonitorApp
    //
    //  Created by Pat Govan on 3/30/25.
    //

import SwiftUI

@main
struct AudiioMonitorAppApp: App {
    @StateObject private var processor = AudioProcessor()
    var body: some Scene {
        WindowGroup {
        NavigationView {
                AudioMonitorView()
                    .environmentObject(processor)

                    .navigationTitle("Audio Monitor")
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            NavigationLink(destination: LogViewerView()) {
                                Label("View Log", systemImage: "doc.text.magnifyingglass")
                            }
                        }
                    }
            }
        }
    }
}
