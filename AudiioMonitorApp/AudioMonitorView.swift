/*
 The needle responsiveness is based on dBFS (decibels relative to full scale), not traditional analog VU dB.
 •    The function vuFromDbFS(_ db: Float) receives input in dBFS, which comes from AudioStats.left and AudioStats.right values (also dBFS).
 •    It then maps this dBFS range (from -80 dBFS to 0 dBFS) to a nonlinear scale approximating analog VU behavior:
 •   Calibrated zone
 ,,,
 case -20 ... -12:
 return 0 + (clamped + 20) * 0.375
 ,,,
 •    The needle’s final position is determined by VUMeterPreviewWrapper(leftLevel: vuFromDbFS(smoothedLeft), ...).
 
 So, to summarize:
 •    Input: dBFS (digital domain, with 0 dBFS as max possible level)
 •    Processing: Translated via vuFromDbFS(...) to approximate a VU-like scale
 •    Needle behavior: Tied directly to this transformed dBFS-derived value
 */




import SwiftUI
import Combine



struct AudioMonitorView: View {
    
    @StateObject var viewModel: AudioMonitorViewModel
    @StateObject var deviceManager: AudioDeviceManager
    @State private var hasPickerBeenUsed: Bool = false
    @State private var didAutoSelectDevice = false
    
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
    
    private func levelCategory(_ dbfs: Float) -> String {
        switch dbfs {
            case ..<(-60): return "Silent"
            case -60..<(-30): return "Low"
            case -30..<(-10): return "Medium"
            case -10...0: return "High"
            default: return "Unknown"
        }
    }
    
        // Categorizes detection status for a given dBFS value
    private func detectionStatus(for dbfs: Float) -> (label: String, color: Color) {
        switch dbfs {
            case ..<(-60): return ("⚠️ Low Detect", .orange)
            case -60..<(-10): return ("✅ Good Detection", .green)
            case -10...0: return ("❌ Over Detection", .red)
            default: return ("Unknown", .gray)
        }
    }
    
    @State private var smoothedLeft: Float = -80.0
    @State private var smoothedRight: Float = -80.0
    
    private func updateSmoothedLevels(from stats: AudioStats) {
        let smoothing: Float = 0.1
        smoothedLeft = smoothing * stats.left + (1 - smoothing) * smoothedLeft
        smoothedRight = smoothing * stats.right + (1 - smoothing) * smoothedRight
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Group {
                VStack(spacing: 28) {
                        // Display selected input
                    Text("🎙 Current Input: \(deviceManager.selected.displayName)")
                        .font(.headline)
                        .padding(.leading)
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
                                    didAutoSelectDevice = false
                                    print("🎯 Selected system default device: \(match.displayName)")
                                } else if let fallback = deviceManager.devices.first {
                                    deviceManager.selected = fallback
                                    didAutoSelectDevice = false
                                    print("⚠️ Fallback selected: \(fallback.displayName)")
                                }
                                
                                    // Ensure monitoring is triggered for selected device
                                viewModel.selectInputDevice(deviceManager.selected)
                                viewModel.startMonitoring()
                                
                                    // Reset flag after initial setup is complete
                                hasPickerBeenUsed = false
                            }
                        }
                        
                    }
                    .onChange(of: deviceManager.selected) { _, newValue in
                        hasPickerBeenUsed = true
                        viewModel.selectInputDevice(newValue)
                        viewModel.startMonitoring()
                    }
                    .padding(.horizontal, 20)
                        // Visual monitoring
                    ZStack(alignment: .top) {
                        VUMeterPreviewWrapper(
                            leftLevel: vuFromDbFS(smoothedLeft),
                            rightLevel: vuFromDbFS(smoothedRight)
                        )
                        .frame(height: 240)
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1)
                    }
                    .padding(.horizontal)
                    .onChange(of: viewModel.latestStats) { _, newStats in
                        updateSmoothedLevels(from: newStats)
                    }
                    
                    Text("Use System Setting > Sound > Input to change the actual Input device.")
                        .font(.headline)
                        .foregroundColor(hasPickerBeenUsed ? .orange : .gray)
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Left: \(vuFromDbFS(viewModel.latestStats.left), specifier: "%.1f") VU (\(viewModel.latestStats.left, specifier: "%.1f") dBFS)")
                            Text("Right: \(vuFromDbFS(viewModel.latestStats.right), specifier: "%.1f") VU (\(viewModel.latestStats.right, specifier: "%.1f") dBFS)")
                        }
                        .frame(height: 20)
                        
                        Text("Level: \(levelCategory(viewModel.latestStats.left)) (L) | \(levelCategory(viewModel.latestStats.right)) (R)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 10) {
                            let leftStatus = detectionStatus(for: viewModel.latestStats.left)
                            let rightStatus = detectionStatus(for: viewModel.latestStats.right)
                            
                            Text("L: \(leftStatus.label)").foregroundColor(leftStatus.color)
                            Text("R: \(rightStatus.label)").foregroundColor(rightStatus.color)
                        }
                        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal,25)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 25)
        
    }
}


#Preview("Audio Monitor View Preview", traits: .sizeThatFitsLayout) {
    let audioManager: AudioManagerProtocol = AudioManager()
    let logManager: LogManagerProtocol = LogManager(audioManager: audioManager)
    let deviceManager = AudioDeviceManager(audioManager: audioManager)
    let viewModel = AudioMonitorViewModel(audioManager: audioManager, logManager: logManager)
    
    return AudioMonitorView(viewModel: viewModel, deviceManager: deviceManager)
}
