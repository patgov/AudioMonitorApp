import SwiftUI
import Combine
import WidgetKit

    /// ViewModel responsible for driving the audio monitoring UI.
    /// Observes real-time audio levels, device selection, and status indicators.
    /// Integrates with a conforming AudioManager and LogManager.
    ///
/*
 A calibrationOffset was added to AudioMonitorViewModel, that fine-tunes the VU meter display to better match system input levels. Adjust calibrationOffset adjustments have been made, -6.0 to reduce perceived levels.
 */
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
    
        /// Calibration offset applies to both left and right levels (in dB).
    public var calibrationOffset: Float = -6.0
    @Published public var selectedInputDevice: InputAudioDevice = .none
    @Published public var showInputSelectionMessage: Bool = false
    @Published public var inputPickerWasUsed: Bool = false
    
    public func setInputPickerUsed(_ used: Bool) {
        inputPickerWasUsed = used
    }
    
        // MARK: - Initialization and Subscriptions
    
    public init(audioManager: some AudioManagerProtocol, logManager: some LogManagerProtocol) {
        self.audioManager = audioManager
        self.logManager = logManager
        
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            audioManager.audioStatsStream
                .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] stats in
                    guard let self = self else { return }
                    guard stats.left != self.latestStats.left || stats.right != self.latestStats.right else { return }
                    print("📥 AudioMonitorViewModel received throttled stats: \(stats)")
                    self.latestStats = stats
                    self.stats = stats
                    print("🎯 Runtime leftLevel with offset: \(stats.left + calibrationOffset)")
                    self.leftLevel = stats.left + calibrationOffset
                    self.rightLevel = stats.right + calibrationOffset
                    self.logManager.update(stats: stats)
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
                    self?.showInputSelectionMessage = (device != .none)
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
        
            // Start publishing to UserDefaults for widget updates
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                let defaults = UserDefaults(suiteName: "group.us.govango.AudioMonitorApp")
                let left = self.leftLevel
                let right = self.rightLevel
                defaults?.set(left, forKey: "leftLevel")
                defaults?.set(right, forKey: "rightLevel")
                defaults?.set(Date(), forKey: "lastUpdate")
                WidgetCenter.shared.reloadAllTimelines()
            }
            .store(in: &cancellables)
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
    
        /// Simulates live audio level updates for preview or testing
    public func updateLevels(left: Float, right: Float) {
        self.leftLevel = left
        self.rightLevel = right
    }
    
#if DEBUG
    public func _injectPreviewStats(_ stats: AudioStats) {
        self.latestStats = stats
    }
#endif
}

#if DEBUG
extension AudioMonitorViewModel {
    static var preview: AudioMonitorViewModel {
        let dummyAudioManager = DummyAudioManager()
        let dummyLogManager = PreviewSafeLogManager()
        let vm = AudioMonitorViewModel(audioManager: dummyAudioManager, logManager: dummyLogManager)
        vm._injectPreviewStats(AudioStats(left: -6.5, right: -5.2, inputName: "MockMic", inputID: 42))
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task {
                await MainActor.run {
                    dummyAudioManager.simulateAudioLevels(
                        left: -10 + Float.random(in: -3...3),
                        right: -12 + Float.random(in: -3...3)
                    )
                }
            }
        }
        return vm
    }
}
#endif
