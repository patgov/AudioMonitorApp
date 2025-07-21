import Foundation
import Combine
import OSLog

@MainActor
public final class AudioDeviceManager: ObservableObject {
    @Published public var devices: [InputAudioDevice] = []
    @Published public var selected: InputAudioDevice = .none {
            // Note: `selected` is a value, not a function. Do not use `selected()` — this will cause a runtime error.
        didSet {
            guard selected != .none else {
                Logger.audioManager.warning("🚫 Ignored re-selection of .none device")
                return
            }
            if oldValue != selected {
                selectDevice(selected)
            }
        }
    }

    @Published public private(set) var deviceNameForDisplay: String = "🛑 None"

    private let audioManager: any AudioManagerProtocol
    private let storageKey = "AudioMonitor.SelectedDeviceID"
    private var cancellable: AnyCancellable?

    public init(audioManager: any AudioManagerProtocol) {
        self.audioManager = audioManager

        self.cancellable = audioManager.inputDevicesStream
            .receive(on: RunLoop.main)
            .sink { [weak self] deviceList in
                self?.devices = deviceList.sorted().filter(\.isSelectable)
                self?.selectStoredOrDefault(from: deviceList)
            }
    }

    private func selectStoredOrDefault(from list: [InputAudioDevice]) {
        let sorted = list.sorted()
        let activeDevices = sorted.filter { $0.isSelectable && $0.hasRecentActivity }
        if let active = activeDevices.first {
            updateSelected(active, reason: "🎯 Auto-selected active device")
            return
        }

        if let storedID = UserDefaults.standard.string(forKey: storageKey),
           let stored = sorted.first(where: { $0.id == storedID }) {
            updateSelected(stored, reason: "🔁 Restored from UserDefaults")
            return
        }

        if let hardware = sorted.first(where: { !$0.isBlackHole && !$0.isVirtual && $0.isSelectable }) {
            updateSelected(hardware, reason: "🎯 Auto-selected real input device")
            return
        }

        if let blackHole = sorted.first(where: { $0.isBlackHole }) {
            updateSelected(blackHole, reason: "🎯 Auto-selected BlackHole")
            return
        }

        if let builtIn = sorted.first(where: { $0.name.lowercased().contains("built-in") }) {
            updateSelected(builtIn, reason: "🎯 Auto-selected Built-in")
            return
        }

        if let system = sorted.first(where: { $0.isSystemDefault }) {
            updateSelected(system, reason: "🎯 Auto-selected system default")
            return
        }

        if let fallback = sorted.first {
            guard fallback != selected else {
                Logger.audioManager.warning("⚠️ Fallback already selected: \(fallback.description, privacy: .public)")
                return
            }
            updateSelected(fallback, reason: "⚠️ Fallback selected")
            Logger.audioManager.warning("⚠️ Fallback selected to: \(fallback.description, privacy: .public)")
            return
        }

        Logger.audioManager.error("❌ No valid input device found for selection.")
    }

    public func selectDevice(_ device: InputAudioDevice) {
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
        selected = device
        deviceNameForDisplay = device.displayName
        print("🎚 [Debug] Updated selected device: \(device.displayName)")
        UserDefaults.standard.set(device.id, forKey: storageKey)
        audioManager.selectDevice(device)

        Logger.audioManager.info("\(reason): \(device.description, privacy: .public)")
    }

    public func resetSelection() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        Logger.audioManager.info("🔄 Cleared saved audio device selection")
    }


    public func fetchAvailableDevices() {
        Logger.audioManager.debug("🔍 Starting device fetch")
        print("🔍 [Debug] fetchAvailableDevices() triggered")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.startDeviceFetch()
        }
    }

    private func startDeviceFetch() {
        audioManager.start()
        self.cancellable?.cancel()
        self.cancellable = audioManager.inputDevicesStream
            .receive(on: RunLoop.main)
            .sink { [weak self] deviceList in
                Logger.audioManager.debug("📦 Fetched \(deviceList.count) devices")
                print("📦 [Debug] Device list: \(deviceList.map { $0.displayName })")
                print("🧪 Raw device list: \(deviceList.map { "\($0.displayName) [selectable: \($0.isSelectable)]" })")
                let filtered = deviceList.sorted().filter(\.isSelectable)
                print("✅ Filtered device list: \(filtered.map(\.displayName))")
                self?.devices = filtered
                self?.selectStoredOrDefault(from: deviceList)
                if deviceList.isEmpty {
                    Logger.audioManager.warning("❌ No devices fetched.")
                    print("❌ [Debug] Device list is empty")
                }
            }
    }
}
