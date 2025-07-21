    //
    //  DevicePickerView.swift
    //  AudioMonitorApp
    //
    //  Created by Pat Govan on 6/8/25.
    //

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

#Preview {
    DevicePickerView(
        selectedDevice: .constant(InputAudioDevice.preview),
        availableDevices: [InputAudioDevice.preview]
    )
}
