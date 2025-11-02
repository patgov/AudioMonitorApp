import CoreAudio
import CoreAudioTypes
import AudioToolbox
import AVFoundation
import SwiftUI


struct DiagnosticsDashboardView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let defaultID = AudioDeviceHelpers.defaultInputDeviceID()
            let devices = AudioDeviceHelpers.availableInputDevices()   // <- get actual devices
            
            if let def = defaultID,
               let match = devices.first(where: { $0.id == def }) {    // <- compare by `id`
                Text("🎧 Using: \(match.name)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            
                // ... rest of your dashboard UI ...
        }
    }
}
