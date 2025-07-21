import SwiftUI
import Combine


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
    @State private var testSignalTimer: Timer? = nil
    @State private var showAudioWarning: Bool = false

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
        VStack(alignment: .leading) {
            Group {
                VStack(spacing: 28) {

                    DevicePickerView(
                        selectedDevice: $deviceManager.selected,
                        availableDevices: deviceManager.devices
                    )
                    .padding(.horizontal, 20)
                    .onChange(of: deviceManager.selected) {
                        hasPickerBeenUsed = true
                        viewModel.selectInputDevice(deviceManager.selected)
                        viewModel.startMonitoring()
                    }

                        // Live audio level data passed to VU meter view
                    VUMeterSectionView(leftLevel: smoothedLeft, rightLevel: smoothedRight)

                        .onAppear {
                            deviceManager.fetchAvailableDevices()

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                let stereoDevices = deviceManager.devices.filter { $0.channelCount >= 2 }

                                if stereoDevices.isEmpty {
                                    print("❌ No stereo devices found. Falling back to first available device.")
                                    if let fallback = deviceManager.devices.first {
                                        deviceManager.selected = fallback
                                        print("⚠️ Using fallback: \(fallback.displayName) [\(fallback.channelCount)ch]")
                                    } else {
                                        print("❌ No devices available for selection.")
                                        return
                                    }
                                } else {
                                    let preferredDevice = stereoDevices.first!
                                    deviceManager.selected = preferredDevice
                                    print("🎯 Forced stereo device: \(preferredDevice.displayName)")
                                }

                                if deviceManager.selected.channelCount < 2 {
                                    print("⚠️ Mono input detected — stereo VU meter will mirror left channel.")
                                }

                                viewModel.selectInputDevice(deviceManager.selected)
                                viewModel.startMonitoring()

                                hasPickerBeenUsed = false
                            }
                        }

                        .onChange(of: viewModel.latestStats) { _, newStats in
                            guard newStats.left != displayStats.left || newStats.right != displayStats.right else { return }

                                // Clamp to VU meter range (-20 to +6) (already in dB VU scale)
                            let clampedLeft = max(-20.0, min(newStats.left, 6.0))
                            let clampedRight = max(-20.0, min(newStats.right, 6.0))

                            smoothedLeft = clampedLeft
                            smoothedRight = clampedRight

                            DispatchQueue.main.async {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    displayStats = AudioStats(
                                        left: clampedLeft,
                                        right: clampedRight,
                                        inputName: newStats.inputName,
                                        inputID: newStats.inputID,
                                        timestamp: newStats.timestamp,
                                        overmodulationCount: newStats.overmodulationCount,
                                        silenceCount: newStats.silenceCount
                                    )
                                }
                            }
                        }

                    AudioWarningView(isVisible: $showAudioWarning)
                        .padding(.horizontal, 25)

                    AudioLevelsSummaryView(
                        leftText: smoothedLeft < -80 ? "-80" : String(format: "%.1f", smoothedLeft),
                        rightText: smoothedRight < -80 ? "-80" : String(format: "%.1f", smoothedRight)
                    )
                    .padding(.horizontal, 25)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 25)

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
        let mockDevice = InputAudioDevice(id: "123", uid: "mock-uid", name: "Mock Mic", audioObjectID: 1, channelCount: 2)
            // ✅ DummyAudioManager is used here only for SwiftUI preview
        let dummyAudioManager = DummyAudioManager()
        let mockDeviceManager = AudioDeviceManager(audioManager: dummyAudioManager)

            // Safely inject mock devices if supported
        mockDeviceManager.injectMockDevices([mockDevice], selected: mockDevice)

        return AudioMonitorView(
            viewModel: AudioMonitorViewModel.preview,
            deviceManager: mockDeviceManager
        )
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                Task { @MainActor in
                    let left = Float.random(in: -20...0)
                    let right = Float.random(in: -20...0)
                    dummyAudioManager.simulateAudioLevels(left: left, right: right)
                }
            }
        }
    }
}
#endif

struct AudioMonitorView_Live: View {
    @StateObject private var audioManager: AudioManager
    @StateObject private var deviceManager: AudioDeviceManager
    @StateObject private var logManager: LogManager

    init() {
        let manager = AudioManager()
        _audioManager = StateObject(wrappedValue: manager)
        _deviceManager = StateObject(wrappedValue: AudioDeviceManager(audioManager: manager))
        _logManager = StateObject(wrappedValue: LogManager(audioManager: manager))
    }

    var body: some View {
        AudioMonitorView(
            viewModel: AudioMonitorViewModel(audioManager: audioManager, logManager: logManager),
            deviceManager: deviceManager
        )
    }
}

#if DEBUG
import Combine
extension DummyAudioManager {
        // Ensure audioStatsSubject exists as a PassthroughSubject<AudioStats, Never>
    var audioStatsSubject: PassthroughSubject<AudioStats, Never> {
            // If DummyAudioManager already has this property, remove this computed property and use the stored one.
            // This is for demonstration only.
        if let existing = objc_getAssociatedObject(self, &audioStatsSubjectKey) as? PassthroughSubject<AudioStats, Never> {
            return existing
        }
        let subject = PassthroughSubject<AudioStats, Never>()
        objc_setAssociatedObject(self, &audioStatsSubjectKey, subject, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return subject
    }
    func simulateAudioLevels(left: Float, right: Float) {
        let stats = AudioStats(left: left, right: right, inputName: "Mock Mic", inputID: 1, timestamp: Date())
        audioStatsSubject.send(stats)
    }
}
private var audioStatsSubjectKey: UInt8 = 0
#endif
