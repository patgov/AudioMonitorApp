    // NOTE: AudioMonitorViewModel is @MainActor-isolated. All property mutation, @Published updates, and Combine publisher/subscriber logic must occur on the main actor. Use Task {@MainActor in ...} if updating state from a background thread. UI code and all Combine sinks should assume main actor context unless explicitly documented otherwise.
    /// ViewModel responsible for driving the audio monitoring UI.
    /// Observes real-time audio levels, device selection, and status indicators.
    /// Integrates with a conforming AudioManager and LogManager.

/*
 calibrationOffset was added to fine-tune the perceived levels on the analog VU meter.
 Default value is -6.0 dB, which adjusts levels downward to better match expected system input levels.
 This allows visual alignment of the needle to match perceived loudness.
 */

    // AudioMonitorViewModel.swift
    // Drives the audio monitoring UI: levels, device selection, status flags.

import SwiftUI
import Combine
import AVFoundation
#if os(macOS)
import AppKit
#endif

@MainActor
final class AudioMonitorViewModel: ObservableObject {
        // Dependencies
    let audioManager: any AudioManagerProtocol
    let logManager: any LogManagerProtocol
    
        // Published state
    @Published private(set) var latestStats: AudioStats = .zero
    @Published var stats: AudioStats = .zero
    @Published var leftLevel: Double = -20.0
    @Published var rightLevel: Double = -20.0
    
        /// Calibration offset (dB) applied to UI levels
    var calibrationOffset: Double = -6.0
    
    @Published var selectedInputDevice: InputAudioDevice = .none
    @Published var showInputSelectionMessage: Bool = false
    @Published var inputPickerWasUsed: Bool = false
    
        // Rate-limit for probe logs (avoid console spam)
    private var lastProbeLog: Date = .distantPast
    
    private var cancellables = Set<AnyCancellable>()
    
    func setInputPickerUsed(_ used: Bool) { inputPickerWasUsed = used }
    
    init(audioManager: some AudioManagerProtocol, logManager: some LogManagerProtocol) {
        self.audioManager = audioManager
        self.logManager = logManager
        
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            audioManager.audioStatsStream
                .receive(on: DispatchQueue.main)
                .sink { [weak self] stats in
                    guard let self else { return }
                    self.latestStats = stats
                    self.stats = stats
                    self.leftLevel = Double(stats.left) + self.calibrationOffset
                    self.rightLevel = Double(stats.right) + self.calibrationOffset
                    self.logManager.update(stats: stats)
                        // ---- Probe: non-zero peak & route check (rate-limited) ----
                    let now = Date()
                    if now.timeIntervalSince(self.lastProbeLog) > 1.0 {
                        self.lastProbeLog = now
                        
                        let engineRunning = self.audioManager.isRunning
                        let selectedName = self.selectedInputDevice.name
                        let selectedID = self.selectedInputDevice.id
                        let reportedName = stats.inputName
                        let reportedID = stats.inputID
                        
                        let leftDB  = stats.left
                        let rightDB = stats.right
                        
                            // Treat <= -119 dBFS as floor (silence)
                        let floorDB: Float = -119.0
                        let hasNonZero = (leftDB > floorDB) || (rightDB > floorDB)
                        
                            // Route mismatch if the device reported by stats differs from UI selection
                        let routeMismatch = (reportedID != 0 && selectedID != 0) && (reportedID != selectedID || reportedName != selectedName)
                        
                        let probeMsg = String(
                            format: "🔎 Probe | running=%@ | selected=\"%@\"[%d] | reported=\"%@\"[%d] | L=%.2f dBFS R=%.2f dBFS | peakNonZero=%@%@",
                            engineRunning ? "true" : "false",
                            selectedName, selectedID,
                            reportedName, reportedID,
                            Double(leftDB), Double(rightDB),
                            hasNonZero ? "true" : "false",
                            routeMismatch ? " | ⚠️ routeMismatch" : ""
                        )
                        print(probeMsg)
                    }
                        // ---- End probe ----
                }
                .store(in: &cancellables)
            
#if DEBUG
            audioManager.audioStatsStream
                .map { ($0.left, $0.right) }
                .receive(on: DispatchQueue.main)
                .sink { lr in
                    print(String(format: "[AudioStats] L: %.2f R: %.2f", lr.0, lr.1))
                }
                .store(in: &cancellables)
#endif
            
            audioManager.selectedInputDeviceStream
                .receive(on: RunLoop.main)
                .sink { [weak self] device in
                    guard let self else { return }
                    if device.id == 0 { return } // ignore placeholder
                    print("🎯 UI selected input: \"\(device.name)\" [id: \(device.id)]")
                    self.selectedInputDevice = device
                    self.showInputSelectionMessage = true
                }
                .store(in: &cancellables)
        }
    }
    
        // Status flags
    var isSilenceDetected: Bool { leftLevel < -60 && rightLevel < -60 }
    var isOvermodulated: Bool { leftLevel > 0 || rightLevel > 0 }
    var engineIsRunning: Bool { audioManager.isRunning }
    var selectedInputName: String { selectedInputDevice.name.isEmpty ? "None" : selectedInputDevice.name }
    
        // Controls
    func stopMonitoring() { audioManager.stop() }
    
    func selectInputDevice(_ device: InputAudioDevice) {
        guard device.id != 0 else {
            print("⚠️ Selected device is placeholder — not starting.")
            return
        }
        
        nonisolated(unsafe) let deviceSnapshot = device
        
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                if granted {
                        // Device selection now triggers engine start automatically.
                    self.audioManager.selectDevice(deviceSnapshot)
                } else {
#if os(macOS)
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
#endif
                }
            }
        }
    }
    
        // Manual injection for previews/tests
    func updateLevels(left: Double, right: Double) {
        self.leftLevel = left
        self.rightLevel = right
    }
    
#if DEBUG
    func _injectPreviewStats(_ stats: AudioStats) {
        self.latestStats = stats
        self.stats = stats
        self.leftLevel = Double(stats.left) + self.calibrationOffset
        self.rightLevel = Double(stats.right) + self.calibrationOffset
    }
#endif
}

#if DEBUG
extension AudioMonitorViewModel {
    static var preview: AudioMonitorViewModel {
            // use lightweight preview-safe dependencies
        let dummyAudioManager = DummyAudioManager()
        let dummyLogManager  = PreviewSafeLogManager()
        
        let vm = AudioMonitorViewModel(
            audioManager: dummyAudioManager,
            logManager: dummyLogManager
        )
            // seed some example levels so the UI looks alive
        vm.updateLevels(left: -10, right: -8)
        return vm
    }
}
#endif
