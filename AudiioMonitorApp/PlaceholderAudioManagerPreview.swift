//
//  Xcode called PlaceholderAudioManagerPreview.swift
//  AudiioMonitorApp
//
//  Created by Pat Govan on 4/26/25.
//

import SwiftUI

struct PlaceholderAudioManagerPreview: View {
    @StateObject private var audioManager = PlaceholderAudioManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Available Input Devices:")
                .font(.headline)
            ForEach(audioManager.availableInputDevices, id: \.self) { device in
                Text("• \(device)")
            }

            Divider()

            Text("Left Level: \(String(format: "%.1f", audioManager.leftLevel)) dB")
            Text("Right Level: \(String(format: "%.1f", audioManager.rightLevel)) dB")
            Text("Input Name: \(audioManager.inputName)")
            Text("Input ID: \(audioManager.inputID)")
        }
        .padding()
        .frame(width: 400, height: 300)
    }
}

#Preview {
    PlaceholderAudioManagerPreview()
}

#Preview {
    struct SimulatedLevelsView: View {
        @StateObject private var dummy = PlaceholderAudioManager()

        var body: some View {
            VStack {
                Text("Placeholder Audio Manager Preview")
                    .font(.title2)
                    .bold()
                    .padding()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Input Devices:")
                        .bold()
                    ForEach(dummy.availableInputDevices, id: \.self) { device in
                        Text("- \(device)")
                    }

                    Text("Left Level: \(String(format: "%.1f", dummy.leftLevel)) dB")
                    Text("Right Level: \(String(format: "%.1f", dummy.rightLevel)) dB")
                }
                .padding()

                Spacer()
            }
            .onAppear {
                simulateNeedleMovement()
            }
        }

        private func simulateNeedleMovement() {
            Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    dummy.leftLevel = Float.random(in: -60...0)
                    dummy.rightLevel = Float.random(in: -60...0)
                }
            }
        }
    }

    return SimulatedLevelsView()
        .frame(width: 400, height: 300)
}
