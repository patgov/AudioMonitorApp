import SwiftUI
import Combine



struct AudioMonitorView: View {
    
    @StateObject var viewModel: AudioMonitorViewModel
    @StateObject var deviceManager: AudioDeviceManager
    
        /// Converts a dBFS value to analog VU units with clamping
        /// Converts a dBFS value to analog VU units with clamping and nonlinear scaling
    private func vuFromDbFS(_ db: Float) -> Float {
        let clamped = max(min(db, 0), -80)
        switch clamped {
            case -80 ... -40:
                return -20 + (clamped + 80) * 0.125  // very low range
            case -40 ... -20:
                return -10 + (clamped + 40) * 0.25   // quiet-mid
            case -20 ... -12:
                return 0 + (clamped + 20) * 0.375    // calibrated zone
            case -12 ... -6:
                return 3 + (clamped + 12) * 0.5      // strong signal
            case -6 ... 0:
                return 6 + (clamped + 6) * 0.1666    // near max
            default:
                return -20
        }
    }
    
    var body: some View {
        VStack(spacing: 32) {
            Group {
                VStack(spacing: 28) {
                        // Display selected input
                    Text("🎙 Current Input: \(deviceManager.selected.displayName)")
                        .font(.headline)
                    
                        // ✅ Input device picker
                    Picker("Input Device", selection: $deviceManager.selected) {
                        ForEach(deviceManager.devices, id: \.id) { device in
                            Text(device.displayName).tag(device)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onAppear {
                        deviceManager.fetchAvailableDevices()
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if deviceManager.devices.isEmpty {
                                print("❌ No devices fetched.")
                            } else {
                                if let defaultID = InputAudioDevice.fetchDefaultInputDeviceID(),
                                   let match = deviceManager.devices.first(where: { $0.audioObjectID == defaultID }) {
                                    deviceManager.selected = match
                                    print("🎯 Selected system default device: \(match.displayName)")
                                } else if let fallback = deviceManager.devices.first {
                                    deviceManager.selected = fallback
                                    print("⚠️ Fallback selected: \(fallback.displayName)")
                                }
                                
                                    // Ensure monitoring is triggered for selected device
                                viewModel.selectInputDevice(deviceManager.selected)
                                viewModel.startMonitoring()
                            }
                        }
                    }
                    .onChange(of: deviceManager.selected) { newValue, _ in
                        viewModel.selectInputDevice(newValue)
                        viewModel.startMonitoring()
                    }
                    
                        // Visual monitoring
                    ZStack(alignment: .top) {
                        VUMeterPreviewWrapper(
                            leftLevel: vuFromDbFS(viewModel.latestStats.left),
                            rightLevel: vuFromDbFS(viewModel.latestStats.right)
                        )
                        .frame(height: 240)
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1)
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Left: \(viewModel.latestStats.left, specifier: "%.1f") dB")
                            Text("Right: \(viewModel.latestStats.right, specifier: "%.1f") dB")
                        }
                        .frame(height: 20)
                        
                        HStack(spacing: 10) {
                            if viewModel.isSilenceDetected {
                                Text("⚠️ Silence Detected").foregroundColor(.orange)
                            }
                            
                            if viewModel.isOvermodulated {
                                Text("❌ Overmodulated").foregroundColor(.red)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
            }
        }
        .padding()
    }
}

//struct VUMeterPreviewWrapper: View {
//    var leftLevel: Float
//    var rightLevel: Float
//    
//    var body: some View {
//        StyledAnalogVUMeterView(leftLevel: leftLevel, rightLevel: rightLevel)
//    }
//}

#Preview("Audio Monitor View Preview", traits: .sizeThatFitsLayout) {
    let audioManager: AudioManagerProtocol = AudioManager()
    let logManager: LogManagerProtocol = LogManager(audioManager: audioManager)
    let deviceManager = AudioDeviceManager(audioManager: audioManager)
    let viewModel = AudioMonitorViewModel(audioManager: audioManager, logManager: logManager)
    
    return AudioMonitorView(viewModel: viewModel, deviceManager: deviceManager)
}
