import SwiftUICore


struct VUMeterNeedleView: View {
    var level: Float
    var label: String

    private let minDB: Float = -60
    private let maxDB: Float = 6
    private let minAngle: Double = -50
    private let maxAngle: Double = 50

    var clampedAngle: Angle {
        let clamped = min(max(level, minDB), maxDB)
        let normalized = Double(clamped - minDB) / Double(maxDB - minDB)
        let degrees = minAngle + normalized * (maxAngle - minAngle)
        return Angle(degrees: degrees)
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                    // Arc ranges
                VUMeterArcRange(start: -20, end: -3).stroke(Color.green, lineWidth: 6)
                VUMeterArcRange(start: -3, end: 0).stroke(Color.yellow, lineWidth: 6)
                VUMeterArcRange(start: 0, end: 3).stroke(Color.white, lineWidth: 6)
                VUMeterArcRange(start: 3, end: 6).stroke(Color.red, lineWidth: 6)
                VUMeterArc().stroke(Color.gray.opacity(0.3), lineWidth: 4)
                VUMeterScale().stroke(Color.white, lineWidth: 1)

                    // Needle
                Needle(angle: clampedAngle)
                    .stroke(Color.red.opacity(level > 0 ? 1.0 : 0.8), lineWidth: 2)
                    .animation(.easeInOut(duration: 0.12), value: clampedAngle)

                Circle()
                    .fill(Color.white)
                    .frame(width: 5, height: 5)
            }
            .aspectRatio(1.2, contentMode: .fit)
            .padding(.bottom, 4)

            Text(label)
                .font(.caption)
                .foregroundColor(.white)
        }
    }
}

