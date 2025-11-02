import SwiftUI

    /// Converts dBFS to VU scale where 0 VU ≈ -20 dBFS
func dbfsToVU(_ dbfs: Float) -> Float {
    return dbfs + 20
}

struct StyledAnalogVUMeterView: View {
    
    var leftLevel: Float
    var rightLevel: Float
    var calibrationOffset: Float = 0
    
    private let minDB: Float = -20
    private let maxDB: Float = 3
    
    private let ticks: [(label: String, dbfs: Float)] = [
        ("-20", -20), ("-15", -15), ("-10", -10), ("-7", -7),
        ("-5", -5), ("-3", -3), ("0", 0), ("+1", 1), ("+2", 2), ("+3", 3)
    ]
    
    private func angle(for level: Float) -> Angle {
        let adjusted = level + calibrationOffset
        let clamped = max(min(adjusted, maxDB), minDB)
        let ratio = Double((clamped - minDB) / (maxDB - minDB))
        return .degrees(-120 + ratio * 240) // center 0 VU
    }
    
        /// Helper to compute angle in degrees for a given dB value (VU scale)
    private func angle(forDB dB: Float) -> Double {
        let clamped = max(min(dB, maxDB), minDB)
        let ratio = (clamped - minDB) / (maxDB - minDB)
        return -120 + Double(ratio * 240) // center 0 VU
    }
    
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                let radius = size * 0.4
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                
                ZStack {
                        // Arc segments
                    ArcSegment(startAngle: angle(forDB: -20), endAngle: angle(forDB: -10), radius: radius)
                        .stroke(Color.gray, lineWidth: 3)
                    ArcSegment(startAngle: angle(forDB: -10), endAngle: angle(forDB: -5), radius: radius)
                        .stroke(Color.orange, lineWidth: 3)
                    ArcSegment(startAngle: angle(forDB: -5), endAngle: angle(forDB: 0), radius: radius)
                        .stroke(Color.green, lineWidth: 3)
                    ArcSegment(startAngle: angle(forDB: 0), endAngle: angle(forDB: 3), radius: radius)
                        .stroke(Color.red, lineWidth: 3)
                    
                        // Tick marks and labels
                    ForEach(ticks, id: \.dbfs) { tick in
                        let tickAngle = angle(for: tick.dbfs)
                        let cosAngle = cos(tickAngle.radians)
                        let sinAngle = sin(tickAngle.radians)
                        let innerRadius = radius - 6.0
                        let tickX = center.x + cosAngle * radius
                        let tickY = center.y + sinAngle * radius
                        let labelX = center.x + cosAngle * (radius + 12)
                        let labelY = center.y + sinAngle * (radius + 12)
                        let tickStartX = center.x + cosAngle * innerRadius
                        let tickStartY = center.y + sinAngle * innerRadius
                        
                        Path { path in
                            path.move(to: CGPoint(x: tickStartX, y: tickStartY))
                            path.addLine(to: CGPoint(x: tickX, y: tickY))
                        }
                        .stroke(Color.black, lineWidth: 2)
                        
                        Text(tick.label)
                            .font(.caption2)
                            .foregroundColor(.black)
                            .position(x: labelX, y: labelY)
                    }
                    
                        // Needle
                        // Determine whether to use average or single channel for mono
                    let isMonoInput = leftLevel == rightLevel
                    let displayedLevel = isMonoInput ? leftLevel : (leftLevel + rightLevel) / 2
                    let needleDB = displayedLevel + calibrationOffset
                    let clampedLevel = max(min(needleDB, maxDB), minDB)
                    let needleAngle = angle(for: clampedLevel)
                    Capsule()
                        .fill(Color.red)
                        .frame(width: 4, height: radius)
                        .offset(y: -radius / 2)
                        .rotationEffect(needleAngle)
                        .position(x: center.x, y: center.y)
                    
                        // Center hub
                    Circle()
                        .fill(Color.black)
                        .frame(width: 8, height: 8)
                        .position(x: center.x, y: center.y)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .padding()
    }
}



#if DEBUG
struct StyledAnalogVUMeterView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            StyledAnalogVUMeterView(leftLevel: -6.0, rightLevel: -6.0)
                .frame(width: 180, height: 180)
                .previewDisplayName("App VU Meter Preview")
        }
    }
}
#endif
