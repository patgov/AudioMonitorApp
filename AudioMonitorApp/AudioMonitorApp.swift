import SwiftUI
import WidgetKit

@main
struct AudioMonitorApp: App {
        // Create shared objects outside the body
    let audioManager = AudioManagerWrapper(manager: AudioManager())
    let logManager: LogManager
    let viewModel: AudioMonitorViewModel
    let deviceManager: AudioDeviceManager

    init() {
        logManager = LogManager(audioManager: audioManager)
        viewModel = AudioMonitorViewModel(audioManager: audioManager, logManager: logManager)
        deviceManager = AudioDeviceManager(audioManager: audioManager)

        print("🎬 App initialized")
        print("🧩 Available input devices at launch: \(deviceManager.devices.map(\.name))")

        viewModel.startMonitoring()

        LogSystem.reportStartupStatus()
            // Inject test values into the widget and trigger reload
        if let defaults = UserDefaults(suiteName: "group.us.govango.AudioMonitorApp") {
            defaults.set(-6.0, forKey: "leftLevel")
            defaults.set(-3.0, forKey: "rightLevel")
            WidgetCenter.shared.reloadAllTimelines()
        } else {
            print("❌ App Group not found. Widget test values not set.")
        }
    }

    var body: some Scene {
        WindowGroup {
            AudioMonitorView(viewModel: viewModel, deviceManager: deviceManager)
                .environment(\.audioManager, audioManager)
                .environment(\.logManager, logManager)
        }
    }
}
