import CoreAudio
import CoreAudioTypes
import AudioToolbox
import AVFoundation
import SwiftUI


struct DiagnosticsDashboardView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let defaultID = InputAudioDevice.fetchDefaultInputDeviceID(),
               let match = InputAudioDevice.fetchAvailableDevices().first(where: { $0.audioObjectID == defaultID && $0.isValid }) {
                Text("🎧 Using: \(match.name)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
                // ... rest of your dashboard UI ...
        }
    }
}

#Preview {
    DiagnosticsDashboardView()
}
