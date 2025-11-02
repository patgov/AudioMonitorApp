import SwiftUI
import CoreAudio

struct AdvancedLogViewerControlView: View {
    let inputDevices: [InputAudioDevice]
    @Binding var selectedDevice: InputAudioDevice
    @Binding var selectedLogLevel: String
    
    let logLevels: [String] = ["INFO", "WARNING", "ERROR"]
    
    var body: some View {
        VStack(spacing: 16) {
            Picker("Audio Input", selection: $selectedDevice) {
                Text("None").tag(InputAudioDevice.none)
                ForEach(inputDevices, id: \.id) { device in
                    Text(device.name).tag(device)
                }
            }
            .pickerStyle(.menu)
            
            Picker("Log Level", selection: $selectedLogLevel) {
                ForEach(logLevels, id: \.self) { level in
                    Text(level).tag(level)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding()
    }
}

#Preview {
    AdvancedLogViewerPreviewWrapper()
}

private struct AdvancedLogViewerPreviewWrapper: View {
    @State private var selectedDevice = InputAudioDevice(id: AudioObjectID(0), name: "None", channelCount: 2)
    @State private var selectedLogLevel = "INFO"
    
    var body: some View {
        AdvancedLogViewerControlView(
            inputDevices: [
                .none,
                InputAudioDevice(id: AudioObjectID(3), name: "BlackHole 2ch", channelCount: 2)
            ],
            selectedDevice: $selectedDevice,
            selectedLogLevel: $selectedLogLevel
        )
    }
}
