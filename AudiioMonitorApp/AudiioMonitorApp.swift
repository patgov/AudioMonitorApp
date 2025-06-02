import SwiftUI

@main
struct AudiioMonitorApp: App {
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
    }
    
    var body: some Scene {
        WindowGroup {
            AudioMonitorView(viewModel: viewModel, deviceManager: deviceManager)
        }
        
    }
}
