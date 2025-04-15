    //
    //  AudioStatsView.swift
    //  AudiioMonitorApp
    //
    //  Created by Pat Govan on 4/1/25.
    //

import SwiftUI

struct AudioStatsView: View {
    @ObservedObject var logManager: LogManager

    init(logManager: LogManager) {
        self.logManager = logManager
    }

    @EnvironmentObject var audioManager: AudioManager
    var silenceCountLeft: Int { logManager.stats.silenceCountLeft.count }
    var silenceCountRight: Int { logManager.stats.silenceCountRight.count }
    var overmodulationCountLeft: Int { logManager.stats.overmodulationCountLeft.count }
    var overmodulationCountRight: Int { logManager.stats.overmodulationCountRight.count }



    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("📈 Audio Stats").font(.headline)

            HStack(spacing: 20) {
                statLabel("L", icon: "waveform", color: .blue)
                statLabel("R", icon: "waveform", color: .green)
            }

            Divider()

            HStack {
                countBlock("🔇 Silence", counts: [
                    silenceCountLeft,
                    silenceCountRight
                ])
                countBlock("🚨 Overmod", counts: [
                    overmodulationCountLeft,
                    overmodulationCountRight
                ])
            }

            Button("Reset Stats", action: {
              logManager.resetStats()
            })
            .padding(.top, 10)
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(radius: 4)
    }

    func statLabel(_ channel: String, icon: String, color: Color) -> some View {
        Label("Channel \(channel)", systemImage: icon)
            .foregroundStyle(color)
            .font(.subheadline)
    }

    func countBlock(_ title: String, counts: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).bold()
            HStack(spacing: 16) {
                Text("L: \(counts[0])").monospacedDigit()
                Text("R: \(counts[1])").monospacedDigit()
            }
        }
    }
}

#Preview {
    AudioStatsView(logManager: LogManager.previewInstance)
}
