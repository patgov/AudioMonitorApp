import SwiftUI
import Combine
import CoreAudio

struct AudioMonitorView: View {
    
    @StateObject var viewModel: AudioMonitorViewModel
    @StateObject var deviceManager: AudioDeviceManager
    @State private var hasPickerBeenUsed: Bool = false
    @State private var didAutoSelectDevice = false
    @State private var isTestSignalEnabled: Bool = false
    @State private var testSignalValue: Float = 0.0
    @State private var smoothedLeft: Float = -20.0
    @State private var smoothedRight: Float = -20.0
    @State private var displayStats: AudioStats = .zero
    @State private var showAudioWarning: Bool = false
    @State private var leftLevelDB: Float = -120
    @State private var rightLevelDB: Float = -120
    
        // Map dBFS (-60..0) to 0..1 for level bars
    private func levelFraction(_ db: Float) -> CGFloat {
        let clamped = max(-60.0, min(db, 0.0))
        return CGFloat((clamped + 60.0) / 60.0)
    }
    
        // Timer publisher for test signal
    private let timerPublisher = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    init(viewModel: AudioMonitorViewModel, deviceManager: AudioDeviceManager) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _deviceManager = StateObject(wrappedValue: deviceManager)
#if !DEBUG
        if deviceManager.audioManager is DummyAudioManager {
            assertionFailure("❌ DummyAudioManager should not be used in production runtime.")
        }
#endif
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 5) {
                    // Title
                Text("Stereo VU Meter")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                
                    // Centered input device name under the title
                Text("Input: \(deviceManager.selected.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                
                    // Meters centered with horizontal padding
                AnalogVUMeterView(leftLevel: $smoothedLeft, rightLevel: $smoothedRight)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 24)
                    .onAppear {
                            // Auto-adopt the system default mic and kick the pipeline
                        deviceManager.fetchAvailableDevices()
                        viewModel.selectInputDevice(deviceManager.selected)
                    }
                
            }
            .padding(.bottom, 20)
        
        }
        .onChange(of: viewModel.latestStats) { _, newStats in
            Task { @MainActor in
                    // Only use levels — we don't surface AudioStats in UI
                var clampedLeft = max(-120.0, min(newStats.left, 6.0))
                var clampedRight = max(-120.0, min(newStats.right, 6.0))
                
                    // Mirror mono sources so analog meter stays stereo
                if newStats.right <= -119.9, newStats.left > -119.9 { clampedRight = clampedLeft }
                if newStats.left  <= -119.9, newStats.right > -119.9 { clampedLeft  = clampedRight }
                
                smoothedLeft = clampedLeft
                smoothedRight = clampedRight
                
              
            }
        }
        
    }
}

#if DEBUG
extension AudioDeviceManager {
    func injectMockDevices(_ devices: [InputAudioDevice], selected: InputAudioDevice) {
        let mutableManager = self
        mutableManager.devices = devices
        mutableManager.selected = selected
    }
}
#endif

#if DEBUG
struct AudioMonitorView_Previews: PreviewProvider {
    static var previews: some View {
        let mockDevice = InputAudioDevice(id: 1, name: "Mock Mic", channelCount: 2)
        let dummyAudioManager = DummyAudioManager()
        let mockDeviceManager = AudioDeviceManager(audioManager: dummyAudioManager)
        
        mockDeviceManager.injectMockDevices([mockDevice], selected: mockDevice)
        
        let timerRef = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
        
        return AudioMonitorView(
            viewModel: AudioMonitorViewModel.preview,
            deviceManager: mockDeviceManager
        )
        .onReceive(timerRef) { _ in
            Task { @MainActor in
                let left = Float.random(in: -20...0)
                let right = Float.random(in: -20...0)
                dummyAudioManager.simulateAudioLevels(left: left, right: right)
            }
        }
        
    }
    
}
#endif

private struct LevelBar: View {
    var value: CGFloat // 0..1
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.green)
                    .frame(width: geo.size.width * max(0, min(value, 1)))
            }
        }
        .frame(height: 10)
        .accessibilityIdentifier("LevelBar")
    }
}

struct AudioMonitorView_Live: View {
    private let audioManager: any AudioManagerProtocol
    @StateObject private var deviceManager: AudioDeviceManager
    @StateObject private var logManager: LogManager
    
    init() {
        let manager = AudioManager()
        self.audioManager = manager
        _deviceManager = StateObject(wrappedValue: AudioDeviceManager(audioManager: manager))
        _logManager     = StateObject(wrappedValue: LogManager(audioManager: manager))
    }
    
    var body: some View {
        AudioMonitorView(
            viewModel: AudioMonitorViewModel(audioManager: audioManager, logManager: logManager),
            deviceManager: deviceManager
        )
    }
}
