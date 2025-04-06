import SwiftUI

@main
struct AudiioMonitorApp: App {
    @StateObject private var logManager: LogManager
    @StateObject private var audioManager: AudioManager
    
    init() {
        let logger = LogManager.shared
        let processor = AudioProcessor()
        _logManager = StateObject(wrappedValue: logger)
        _audioManager = StateObject(wrappedValue: AudioManager(processor: processor, logManager: logger))
    }
    var body: some Scene {
        WindowGroup {
           NavigationView {
                AudioMonitorView()
                    .environmentObject(audioManager)
                    .environmentObject(logManager)
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
