
import SwiftUI
import CoreAudio

#Preview {
    AudioMonitorPreviewWrapper()
}

private struct AudioMonitorPreviewWrapper: View {
        // ⬇︎ Static so nothing about `self` is captured
    private static let dummy = DummyAudioManager()
    
    @StateObject private var deviceManager: AudioDeviceManager
    @StateObject private var viewModel: AudioMonitorViewModel
    
    
    let mockDevice = InputAudioDevice(
        id: AudioObjectID(1),
        name: "🎙️ Mock Mic",
        channelCount: 2
    )

    
    init() {
        let dummy = Self.dummy
        
        let mock = InputAudioDevice(id: AudioObjectID(1), name: "🎙️ Mock Mic", channelCount: 2)
        
        let dm = AudioDeviceManager(audioManager: dummy)
        dm.injectMockDevices([mock], selected: mock)
        
        _deviceManager = StateObject(wrappedValue: dm)
        _viewModel     = StateObject(wrappedValue: AudioMonitorViewModel(
            audioManager: dummy,
            logManager: PreviewSafeLogManager()
        ))
    }
    
    var body: some View {
        AudioMonitorView(viewModel: viewModel, deviceManager: deviceManager)
            .onAppear { viewModel.updateLevels(left: -10.0, right: -8.0) }
    }
}
