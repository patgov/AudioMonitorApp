

import SwiftUI

struct DevicePickerView: View {
    @Binding var selectedDevice: InputAudioDevice
    var availableDevices: [InputAudioDevice]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Input Device")
                .font(.headline)
            Picker("Input Device", selection: $selectedDevice) {
                ForEach(availableDevices, id: \.id) { device in
                    Text(device.name).tag(device)
                }
            }
            .pickerStyle(MenuPickerStyle())
        }
        .padding()
    }
}

#if DEBUG
import CoreAudio

extension InputAudioDevice {
    nonisolated(unsafe) static let preview = InputAudioDevice(id: AudioObjectID(1), name: "Mock Mic", channelCount: 2)
}
#endif


#Preview {
    DevicePickerView(
        selectedDevice: .constant(InputAudioDevice.preview),
        availableDevices: [InputAudioDevice.preview]
    )
}
