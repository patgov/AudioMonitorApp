import SwiftUI

@main
struct AudiioMonitorApp: App {
    private let processor = AudioProcessor()
    private let audioManager: AudioManager
    @StateObject private var logManager: LogManager
    @StateObject private var viewModel: AudioMonitorViewModel

    init() {
            // Step 1: Create log manager with a temporary placeholder
        let temporaryLogManager = LogManager(audioManager: nil)

            // Step 2: Now that we have the log manager, we can initialize the audio manager
        let actualAudioManager = AudioManager(processor: processor, logManager: temporaryLogManager)

            // Step 3: Inject audioManager back into the log manager
        temporaryLogManager.audioManager = actualAudioManager

            // Assign to properties
        self.audioManager = actualAudioManager
        _logManager = StateObject(wrappedValue: temporaryLogManager)
        _viewModel = StateObject(wrappedValue: AudioMonitorViewModel(audioManager: actualAudioManager, logManager: temporaryLogManager))
    }

    var body: some Scene {
        WindowGroup {
            AudioMonitorView(viewModel: viewModel)
                .environmentObject(audioManager)
                .environmentObject(logManager)
        }
    }
}
