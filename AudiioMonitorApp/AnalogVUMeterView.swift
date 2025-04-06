import SwiftUI

struct AnalogVUMeterView: View {
    var leftLevel: Float
    var rightLevel: Float

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.gray, lineWidth: 2)
                )
                .shadow(radius: 5)

            VStack(spacing: 16) {
                Text("VU Meter")
                    .font(.headline)
                    .foregroundColor(.white)

                HStack {
                    NeedleMeter(level: leftLevel, label: "L")
                    NeedleMeter(level: rightLevel, label: "R")
                }
            }
            .padding()
        }
        .aspectRatio(2, contentMode: .fit)
        .padding()
    }
}

struct NeedleMeter: View {
    var level: Float
    var label: String

    private let minDb: Float = -80.0
    private let maxDb: Float = 0.0
    private let minAngle: Angle = .degrees(-50)
    private let maxAngle: Angle = .degrees(50)

    private func needleAngle(for level: Float) -> Angle {
        let clamped = max(min(level, maxDb), minDb)
        let ratio = (clamped - minDb) / (maxDb - minDb)
        return Angle(degrees: Double(minAngle.degrees + (maxAngle.degrees - minAngle.degrees) * Double(ratio)))
    }
    

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 3)
                    .background(Circle().fill(Color.black))
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2, height: geo.size.height * 0.4)
                    .offset(y: -geo.size.height * 0.2)
                    .rotationEffect(needleAngle(for: level))
                    .animation(.easeOut(duration: 0.1), value: level)
                Text(label)
                    .foregroundColor(.white)
                    .offset(y: geo.size.height * 0.3)
            }
            .frame(width: geo.size.width, height: geo.size.width)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding()
    }

}
