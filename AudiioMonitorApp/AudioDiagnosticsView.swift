import SwiftUI

struct AudioDiagnosticsView: View {
    let stats: AudioStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audio Diagnostics")
                .font(.headline)
            
            Text("Left Level: \(String(format: "%.1f", stats.left)) dB")
                .foregroundColor(stats.left > -1 ? .red : .primary)
            
            Text("Right Level: \(String(format: "%.1f", stats.right)) dB")
                .foregroundColor(stats.right > -1 ? .red : .primary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.2)))        .padding()
    }
}

struct AudioDiagnosticsView_Previews: PreviewProvider {
    static var previews: some View {
        AudioDiagnosticsView(stats: AudioStats(left: -22.5, right: -0.5, inputName: "Preview Mic", inputID: 0))
    }
}
