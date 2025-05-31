import Foundation
import SwiftUI

enum PreviewProviderFactory {
    
    @MainActor static func makeLogManagerPreview() -> LogManager {
        let audioManager = AudioManager()
        let logManager = LogManager(audioManager: audioManager)
        
        logManager.addWarning(message: "Mic disconnected", channel: 0, value: -80.0)
        logManager.addError(message: "Overmodulation spike", channel: 1, value: -0.2)
        
        return logManager
    }
    
    @MainActor static func makeAudioMonitorViewModelPreview() -> AudioMonitorViewModel {
        let audioManager = AudioManager()
        let logManager = LogManager(audioManager: audioManager)
        return AudioMonitorViewModel(audioManager: audioManager, logManager: logManager)
    }
    
    @MainActor static func makeAudioMonitorViewPreview() -> some View {
        let viewModel = makeAudioMonitorViewModelPreview()
        return AudioMonitorView(viewModel: viewModel, deviceManager: AudioDeviceManager(audioManager: DummyAudioManager()))
    }
}
