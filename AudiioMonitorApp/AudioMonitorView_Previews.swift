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
        AudioMonitorView(viewModel: viewModel, deviceManager: AudioDeviceManager(audioManager: DummyAudioManager()))
    }
}
