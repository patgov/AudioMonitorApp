import SwiftUI

#Preview {
    AudioMonitorPreviewWrapper()
}

private struct AudioMonitorPreviewWrapper: View {
    @StateObject private var viewModel = AudioMonitorViewModel(
        audioManager: DummyAudioManager(),
        logManager: PreviewSafeLogManager()
    )
    
    var body: some View {
        let mockDevice = InputAudioDevice(
            id: "123",
            uid: "mock-uid",
            name: "🎙️ Mock Mic",
            audioObjectID: 1,
            channelCount: 2
        )
        
        let mockDeviceManager = AudioDeviceManager(audioManager: DummyAudioManager())
        mockDeviceManager.injectMockDevices([mockDevice], selected: mockDevice)
        
        return AudioMonitorView(viewModel: viewModel, deviceManager: mockDeviceManager)
            .onAppear {
                viewModel.updateLevels(left: -10.0, right: -8.0)
            }
    }
}
