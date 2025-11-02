import Foundation
import CoreAudio
import Combine
import OSLog
import SwiftUI

@MainActor
final class AudioDeviceManager: ObservableObject, View {
    @Published var devices: [InputAudioDevice] = []
    @Published var selected: InputAudioDevice = .none {
        didSet {
            if isSystemDrivenUpdate { return }
            guard selected != .none else {
                Logger.audioManager.warning("🚫 Ignored re-selection of .none device")
                self.deviceNameForDisplay = "🛑 None"
                return
            }
            if oldValue != selected {
                self.deviceNameForDisplay = selected.displayName
                selectDevice(selected)
            }
        }
    }
    
    @Published private(set) var deviceNameForDisplay: String = "🛑 None"
        // Prevent feedback loops when the system (AudioManager) drives selection changes
    private var isSystemDrivenUpdate = false
    
    let audioManager: any AudioManagerProtocol
    private let storageKey = "AudioMonitor.SelectedDeviceID"
    private var cancellables = Set<AnyCancellable>()
    private var lastSystemAdoptionAt: Date? = nil
    private let SYSTEM_CHANGE_GRACE: TimeInterval = 5.0
    
    init(audioManager: any AudioManagerProtocol) {
        self.audioManager = audioManager
        self.cancellables = Set<AnyCancellable>()
        audioManager.inputDevicesStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] deviceList in
                Task { @MainActor in
                    guard let self else { return }
                    self.devices = deviceList.sorted().filter(\.isSelectable)
                        // Avoid selection churn if we just adopted a system change
                    if let t = self.lastSystemAdoptionAt, Date().timeIntervalSince(t) < self.SYSTEM_CHANGE_GRACE {
                        Logger.audioManager.debug("⏱️ Skipping auto-select (within grace window after system change)")
                        return
                    }
                    self.selectStoredOrDefault(from: deviceList)
                }
            }
            .store(in: &cancellables)
        
        audioManager.selectedInputDeviceStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSelected in
                Task { @MainActor in
                    guard let self else { return }
                    guard newSelected != .none else { return }
                    self.lastSystemAdoptionAt = Date()
                        // Break feedback loop: mark as system-driven while we assign
                    self.isSystemDrivenUpdate = true
                    self.selected = newSelected
                    self.deviceNameForDisplay = newSelected.displayName
                    UserDefaults.standard.set(Int(newSelected.id), forKey: self.storageKey)
                    self.isSystemDrivenUpdate = false
                    Logger.audioManager.info("🪄 Adopted system-selected device: \(newSelected.description, privacy: .public)")
                }
            }
            .store(in: &cancellables)
    }
    
    private func selectStoredOrDefault(from list: [InputAudioDevice]) {
        if let t = lastSystemAdoptionAt, Date().timeIntervalSince(t) < SYSTEM_CHANGE_GRACE {
            Logger.audioManager.debug("⏱️ Suppressing stored/default selection (within system-change grace window)")
            return
        }
        
        let sorted = list.sorted()
        let selectable = sorted.filter { $0.isSelectable }
        
            // If current selection is still present, keep it
        if selected != .none, selectable.contains(where: { $0.id == selected.id }) {
            deviceNameForDisplay = selected.displayName
            Logger.audioManager.debug("🔎 Keeping current selection: \(self.selected.description, privacy: .public)")
            return
        }
        
            // 1) Prefer current system default if available
        if let system = selectable.first(where: { $0.isSystemDefault }) {
            updateSelected(system, reason: "🎯 Auto-selected system default")
            return
        }
        
            // 2) Prefer active devices next
        if let active = selectable.first(where: { $0.hasRecentActivity }) {
            updateSelected(active, reason: "🎯 Auto-selected active device")
            return
        }
        
            // 3) Restore from UserDefaults if still present
        if let storedID = UserDefaults.standard.value(forKey: storageKey) as? Int,
           let stored = selectable.first(where: { Int($0.id) == storedID }) {
            updateSelected(stored, reason: "🔁 Restored from UserDefaults")
            return
        }
        
            // 4) Prefer a real hardware input, then BlackHole, then Built-in, else first
        if let hardware = selectable.first(where: { !$0.isBlackHole && !$0.isVirtual }) {
            updateSelected(hardware, reason: "🎯 Auto-selected real input device")
            return
        }
        if let blackHole = selectable.first(where: { $0.isBlackHole }) {
            updateSelected(blackHole, reason: "🎯 Auto-selected BlackHole")
            return
        }
        if let builtIn = selectable.first(where: { $0.name.lowercased().contains("built-in") }) {
            updateSelected(builtIn, reason: "🎯 Auto-selected Built-in")
            return
        }
        
        if let fallback = selectable.first {
            guard fallback != selected else {
                Logger.audioManager.warning("⚠️ Fallback already selected: \(fallback.description, privacy: .public)")
                return
            }
            updateSelected(fallback, reason: "⚠️ Fallback selected")
            Logger.audioManager.warning("⚠️ Fallback selected to: \(fallback.description, privacy: .public)")
            return
        }
        
        Logger.audioManager.debug("❌ No valid input device found for selection.")
    }
    
    func selectDevice(_ device: InputAudioDevice) {
        guard device != .none else {
            Logger.audioManager.warning("🚫 Attempted to select .none device")
            return
        }
        audioManager.selectDevice(device)
        Logger.audioManager.info("🎧 Selected device: \(String(describing: device.description), privacy: .public)")
    }
    
    private func updateSelected(_ device: InputAudioDevice, reason: String) {
        guard device != .none else {
            Logger.audioManager.warning("🚫 Attempted to select .none device")
            return
        }
            // Suppress didSet feedback into selectDevice(_:) for system/auto decisions
        isSystemDrivenUpdate = true
        selected = device
        deviceNameForDisplay = device.displayName
        UserDefaults.standard.set(Int(device.id), forKey: storageKey)
        isSystemDrivenUpdate = false
        Logger.audioManager.info("\(reason): \(device.description, privacy: .public)")
    }
    
    func resetSelection() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        Logger.audioManager.info("🔄 Cleared saved audio device selection")
    }
    
    func fetchAvailableDevices() {
        Logger.audioManager.debug("🔍 Starting device fetch")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.startDeviceFetch()
        }
    }
    
    private func startDeviceFetch() {
        audioManager.start()
        audioManager.inputDevicesStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] deviceList in
                Task { @MainActor in
                    guard let self else { return }
                    Logger.audioManager.debug("📦 Fetched \(deviceList.count) devices")
                    let filtered = deviceList.sorted().filter(\.isSelectable)
                    self.devices = filtered
                    guard !deviceList.isEmpty else {
                        Logger.audioManager.warning("❌ No devices fetched.")
                        return
                    }
                    if let t = self.lastSystemAdoptionAt, Date().timeIntervalSince(t) < self.SYSTEM_CHANGE_GRACE {
                        Logger.audioManager.debug("⏱️ Skipping auto-select (within grace window after system change)")
                        return
                    }
                    self.selectStoredOrDefault(from: filtered)
                }
            }
            .store(in: &cancellables)
    }
    
    var body: some View {
        Text("AudioDeviceManager has no visual representation.")
    }
}
