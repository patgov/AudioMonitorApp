import SwiftUI

struct AnalogVUMeterView: View {
    @Binding var leftLevel: Float
    @Binding var rightLevel: Float
    @State private var smoothedLeft: Float = -20.0
    @State private var smoothedRight: Float = -20.0
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Stereo VU Meter")
                .font(.title3.bold())
                .foregroundColor(.yellow)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
            
            HStack(spacing: 20) {
                VStack(spacing: 8) {
                    VUMeterNeedleView(level: smoothedLeft, label: "L")
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                    Text(String(format: "%.1f dBFS", smoothedLeft))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.green)
                }
                .layoutPriority(1)
                
                VStack(spacing: 8) {
                    VUMeterNeedleView(level: smoothedRight, label: "R")
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                    
                    Text(String(format: "%.1f dBFS", smoothedRight))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.green)
                }
                .layoutPriority(1)
                
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .onAppear {
                // Initialize smoothed values so the labels show immediately
            smoothedLeft = leftLevel
            smoothedRight = rightLevel
        }
        .onChange(of: leftLevel) { oldValue, newValue in
                // Animate to new left level
            withAnimation(.linear(duration: 0.08)) {
                smoothedLeft = newValue
            }
        }
        .onChange(of: rightLevel) { oldValue, newValue in
                // Animate to new right level
            withAnimation(.linear(duration: 0.08)) {
                smoothedRight = newValue
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .center)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.black, lineWidth: 2)
        )
    }
}
#Preview("Analog VU Meter Preview", traits: .sizeThatFitsLayout) {
    AnalogVUMeterView(
        leftLevel: .constant(-20.0),
        rightLevel: .constant(-20.0)
    )
    .frame(maxWidth: .infinity, minHeight: 300)
    .padding()
    .background(Color.black)
}




