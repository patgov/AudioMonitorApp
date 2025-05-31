import SwiftUI
import Combine

    /// ViewModel responsible for driving the audio monitoring UI.
    /// Observes real-time audio levels, device selection, and status indicators.
    /// Integrates with a conforming AudioManager and LogManager.
@MainActor
public final class AudioMonitorViewModel: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    public let audioManager: any AudioManagerProtocol
    private let logManager: any LogManagerProtocol
    
        // MARK: - Published State
    
    @Published public private(set) var latestStats: AudioStats = .zero
    @Published public var stats: AudioStats = .zero
    @Published public var leftLevel: Float = -80.0
    @Published public var rightLevel: Float = -80.0
    @Published public var selectedInputDevice: InputAudioDevice = .none
    
        // MARK: - Initialization and Subscriptions
    
    public init(audioManager: some AudioManagerProtocol, logManager: some LogManagerProtocol) {
        self.audioManager = audioManager
        self.logManager = logManager
        
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            audioManager.audioStatsStream
                .receive(on: DispatchQueue.main)
                .sink { [weak self] stats in
                    print("📥 AudioMonitorViewModel received stats: \(stats)")
                    self?.latestStats = stats
                    self?.stats = stats
                    self?.leftLevel = stats.left
                    self?.rightLevel = stats.right
                    self?.logManager.update(stats: stats)
                }
                .store(in: &cancellables)
            
            audioManager.selectedInputDeviceStream
                .receive(on: DispatchQueue.main)
                .sink { [weak self] device in
                        // Accept .none devices for fallback or preview cases
                        // guard device != .none else {
                        //     print("⚠️ Ignoring .none from selectedInputDeviceStream")
                        //     return
                        // }
                    self?.selectedInputDevice = device
                }
                .store(in: &cancellables)
        }
    }
    
        // MARK: - Audio Level Accessors
    
        // MARK: - Status Flags
    
        /// Used to display silence warning in UI. Ensure the UI reserve a fixed frame height (e.g., 20) where this is consumed to avoid jumping.
    public var isSilenceDetected: Bool {
        leftLevel < -60 && rightLevel < -60
    }
    
    public var isOvermodulated: Bool {
        leftLevel > 0 || rightLevel > 0
    }
    
    public var engineIsRunning: Bool {
        (audioManager as? AudioManager)?.isRunning ?? false
    }
    
    public var selectedInputName: String {
        selectedInputDevice.name.isEmpty ? "None" : selectedInputDevice.name
    }
    
        // MARK: - Monitoring Controls
    
    func startMonitoring() {
            // Proceed even if selectedInputDevice is .none, as audioManager may still emit valid stats
            // guard selectedInputDevice != .none else {
            //     print("❌ No audio device selected")
            //     return
            // }
        
        audioManager.selectDevice(selectedInputDevice)
        audioManager.start()
    }
    public func stopMonitoring() {
        audioManager.stop()
    }
    public func selectInputDevice(_ device: InputAudioDevice) {
        guard device != .none else {
            print("⚠️ Selected device is .none — monitoring will not start.")
            return
        }
        
        audioManager.selectDevice(device)
        audioManager.start()
    }
    
#if DEBUG
    public func _injectPreviewStats(_ stats: AudioStats) {
        self.latestStats = stats
    }
#endif
}

    // MARK: - Preview

#if DEBUG
import AudioToolbox

#if DEBUG
private struct AudioMonitorViewModelPreviewWrapper: View {
    let viewModel: AudioMonitorViewModel
    
    init() {
        let dummyAudioManager = DummyAudioManager()
        let dummyLogManager = PreviewSafeLogManager()
        let vm = AudioMonitorViewModel(audioManager: dummyAudioManager, logManager: dummyLogManager)
        vm._injectPreviewStats(AudioStats(left: -6.5, right: -5.2, inputName: "MockMic", inputID: 42))
        self.viewModel = vm
    }
    
    var body: some View {
        Text("Preview left: \(viewModel.leftLevel) dB")
            .padding()
    }
}

#Preview("AudioMonitorViewModel Preview") {
    AudioMonitorViewModelPreviewWrapper()
}
#endif // End of DEBUG wrapper
#endif
    //#endif
