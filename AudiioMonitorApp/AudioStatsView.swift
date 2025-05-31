import SwiftUI

struct AudioStatusView: View {
    let engineRunning: Bool
    let inputName: String?
    let stats: AudioStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Engine: \(engineRunning ? "Running" : "Stopped")", systemImage: "waveform")
            Label("Device: \(inputName ?? "None")", systemImage: "mic.fill")
            Label("L dB: \(String(format: "%.1f", stats.left))", systemImage: "speaker.wave.1.fill")
            Label("R dB: \(String(format: "%.1f", stats.right))", systemImage: "speaker.wave.2.fill")
        }
        .padding()
        .background(Color.gray.opacity(0.15))
        .cornerRadius(10)
    }
}

struct AudioStatsView: View {
    let stats: AudioStats
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Audio Levels")
                .font(.headline)
            
            HStack(spacing: 24) {
                VStack {
                    Text("Left")
                    Text(String(format: "%.1f dB", stats.left))
                        .foregroundColor(stats.left > -1 ? .red : .primary)
                }
                
                VStack {
                    Text("Right")
                    Text(String(format: "%.1f dB", stats.right))
                        .foregroundColor(stats.right > -1 ? .red : .primary)
                }
            }
            .font(.title3)
        }
        .padding()
    }
}

#Preview {
    AudioStatusView(engineRunning: true, inputName: "Built-in Mic", stats: .preview)
    AudioStatsView(stats: .preview)
}
    //focus on building a status view that shows actual engine/device status in-app?
