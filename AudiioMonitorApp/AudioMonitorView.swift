import SwiftUI

    // AudioMonitorView.swift

struct AudioMonitorView: View {
    @ObservedObject var viewModel: AudioMonitorViewModel
    @State private var hasAppeared = false
    
    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                AnalogVUMeterView(
                    leftLevel: $viewModel.leftLevel,
                    rightLevel: $viewModel.rightLevel
                )
             //   .frame(maxWidth: .infinity, maxHeight: .infinity)
                
//                Text(String(format: "L: %.1f dB, R: %.1f dB", viewModel.leftLevel, viewModel.rightLevel))
//                    .foregroundColor(viewModel.leftLevel > 0 || viewModel.rightLevel > 0 ? .red :
//                                        (viewModel.leftLevel >= -3 || viewModel.rightLevel >= -3 ? .yellow : .green))
//                    .font(.caption)
                
//                HStack(spacing: 30) {
//                    DBMeterBar(value: viewModel.leftLevel, label: "L")
//                    DBMeterBar(value: viewModel.rightLevel, label: "R")
//                }
//                
                Text(viewModel.statusText)
                    .foregroundColor(viewModel.statusColor)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding()
            //.frame(minWidth: 200, minHeight: 150)
            .onAppear {
                guard !hasAppeared else { return }
                hasAppeared = true
                viewModel.audioManager.start()
                viewModel.bindToAudioProcessor()
                viewModel.loadLogData()
            }
        }
    }
}

struct DBMeterBar: View {
    let value: Float
    let label: String
    
    var barColor: Color {
        if value > 0 { return .red }
        else if value >= -3 { return .yellow }
        else { return .green }
    }
    
    var body: some View {
        VStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.white)
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 20, height: 100)
                    .cornerRadius(5)
                
                Rectangle()
                    .fill(barColor)
                    .frame(width: 20, height: CGFloat((100 + value) / 100 * 100))
                    .cornerRadius(5)
            }
        }
    }
}

struct AudioMonitorView_Previews: PreviewProvider {
    struct Container: View {
        @StateObject var dummyViewModel: AudioMonitorViewModel = {
            let dummyProcessor = AudioProcessor()
            let dummyAudioManager = DummyAudioManager(processor: dummyProcessor)
            let dummyLogManager = LogManager(audioManager: dummyAudioManager)
            return AudioMonitorViewModel(audioManager: dummyAudioManager, logManager: dummyLogManager)
        }()
        
        var body: some View {
            AudioMonitorView(viewModel: dummyViewModel)
        }
    }
    
    static var previews: some View {
        Container()
            .previewLayout(.sizeThatFits)
    }
}

#Preview {
    let placeholderProcessor = AudioProcessor()
    let placeholderAudioManager = AudioManager(processor: placeholderProcessor, logManager: nil)
    let placeholderLogManager = LogManager(audioManager: placeholderAudioManager)
    let viewModel = AudioMonitorViewModel(audioManager: placeholderAudioManager, logManager: placeholderLogManager)
    
    AudioMonitorView(viewModel: viewModel)
}
