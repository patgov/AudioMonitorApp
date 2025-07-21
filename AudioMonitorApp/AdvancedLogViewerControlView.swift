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
            .pickerStyle(MenuPickerStyle())

            Picker("Log Level", selection: $selectedLogLevel) {
                ForEach(logLevels, id: \.self) { level in
                    Text(level).tag(level)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
        }
        .padding()
    }
}


#Preview {

    AdvancedLogViewerPreviewWrapper()
}

private struct AdvancedLogViewerPreviewWrapper: View {
    @State private var selectedDevice = InputAudioDevice(id: "none", uid: "none", name: "None", audioObjectID: AudioObjectID(0),channelCount: 2)
    @State private var selectedLogLevel = "INFO"

    var body: some View {
        AdvancedLogViewerControlView(
            inputDevices: [
                InputAudioDevice(id: "none", uid: "none", name: "None", audioObjectID: AudioObjectID(0),channelCount: 2),
                InputAudioDevice(id: "blackhole", uid: "blackhole", name: "BlackHole 2ch", audioObjectID: AudioObjectID(3),channelCount: 2)
            ],
            selectedDevice: $selectedDevice,
            selectedLogLevel: $selectedLogLevel
        )
    }
}
