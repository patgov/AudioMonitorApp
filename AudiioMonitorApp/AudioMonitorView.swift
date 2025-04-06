import SwiftUI

struct AudioMonitorView: View {
    @EnvironmentObject var audioManager: AudioManager
    @EnvironmentObject var logManager: LogManager
    @State private var isShowingLogViewer = false
    @State private var isShowingStats = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Audio Monitor")
                .font(.largeTitle)
                .bold()

            AnalogVUMeterView(
                leftLevel: audioManager.processor.leftLevel,
                rightLevel: audioManager.processor.rightLevel
            )
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .padding()

            HStack(spacing: 16) {
                Button("View Log") {
                    isShowingLogViewer.toggle()
                }
                .buttonStyle(.borderedProminent)

                Button(isShowingStats ? "Hide Stats" : "Show Stats") {
                    isShowingStats.toggle()
                }
                .buttonStyle(.bordered)
            }

            if isShowingStats {
                HStack(spacing: 32) {
                    VStack(alignment: .leading) {
                        Text("Left dB:")
                        Text("\(String(format: "%.2f", audioManager.processor.leftLevel)) dB").bold()
                    }
                    VStack(alignment: .leading) {
                        Text("Right dB:")
                        Text("\(String(format: "%.2f", audioManager.processor.rightLevel)) dB").bold()
                    }
                    VStack(alignment: .leading) {
                        Text("Status:")
                        Text(audioManager.processor.isOvermodulated ? "🔴 Overmodulated" :
                                audioManager.processor.isSilent ? "🟡 Silent" : "🟢 Normal")
                        .bold()
                        .foregroundColor(audioManager.processor.isOvermodulated ? .red :
                                            audioManager.processor.isSilent ? .yellow : .green)
                    }
                }
                .font(.title3)
                .padding()
            }

            Spacer()
        }
        .padding()
        .onAppear {
            audioManager.requestPermissionAndStart()
            print("✅ AudioMonitorView appeared")
        }
        .onDisappear {
            audioManager.stop()
        }
        .sheet(isPresented: $isShowingLogViewer) {
            AdvancedLogViewerView(entries: logManager.entries)
                .frame(minWidth: 600, minHeight: 400)
        }
    }
}


#Preview {
    AudioMonitorView()
        .environmentObject(AudioManager(processor: AudioProcessor(), logManager: LogManager.shared))
        .environmentObject(LogManager.shared)
}
