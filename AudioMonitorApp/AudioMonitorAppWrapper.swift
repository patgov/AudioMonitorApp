import SwiftUI



struct AudioMonitorAppWrapper:  View {
    private let audioManager: any AudioManagerProtocol = AudioManager()
    
    @State private var logManager: LogManager?
    @State private var viewModel: AudioMonitorViewModel?
    @State private var deviceManager: AudioDeviceManager?
    
    var body: some View {
        Group {
            if let logManager, let viewModel, let deviceManager {
                AudioMonitorView(viewModel: viewModel, deviceManager: deviceManager)
                    .environment(\.logManager, logManager)
                    .environment(\.audioManager, audioManager)
            } else {
                ProgressView("Starting…")
            }
        }
        .onAppear {
            if logManager == nil {
                let log = LogManager(audioManager: audioManager)
                let dev = AudioDeviceManager(audioManager: audioManager)
                let vm = AudioMonitorViewModel(audioManager: audioManager, logManager: log)
                
                self.logManager = log
                self.deviceManager = dev
                self.viewModel = vm
                
                    //  vm.startMonitoring()
                LogSystem.reportStartupStatus()
            }
        }
    }
}

#if DEBUG
struct AudioMonitorAppWrapper_Previews: PreviewProvider {
    static var previews: some View {
        AudioMonitorAppWrapper()
            .frame(width: 400, height: 300)
            .previewDisplayName("App Preview")
    }
}
#endif
