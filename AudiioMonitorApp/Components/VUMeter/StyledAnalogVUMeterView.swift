import SwiftUI

    /// A analog VU Meter that that shows both dB and dBFS Labels to declare analog and digital level.
    /// A dBFS (decibels relative to full scale) scale measures signal level in digital audio systems, where 0 dBFS represents the maximum possible level. In contrast, an analog VU (Volume Unit) meter is calibrated with 0 VU representing a reference level (typically +4 dBu), not the peak.

struct StyledAnalogVUMeterView: View {
    var leftLevel: Float
    var rightLevel: Float
    
    private let minDB: Float = -20
    private let maxDB: Float = 3
    private let minAngle: Double = -80
    private let maxAngle: Double = 80
    
    var clampedAngle: Angle {
        let clampedLevel = min(max(leftLevel, minDB), maxDB)
        let normalized = (Double(clampedLevel - minDB) / Double(maxDB - minDB))
        let degrees = minAngle + normalized * (maxAngle - minAngle)
        return .degrees(degrees)
    }
    
    var angleForLevel: (Float) -> Angle {
        return { level in
            let clamped = min(max(level, minDB), maxDB)
            let normalized = (Double(clamped - minDB) / Double(maxDB - minDB))
            let degrees = minAngle + normalized * (maxAngle - minAngle)
            return .degrees(degrees)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let arcRadius: CGFloat = geometry.size.width * 0.3
            let centerX = geometry.size.width / 2.0
            let centerY = geometry.size.height * 0.2 + arcRadius
            let tickRadius = arcRadius
            
            ZStack {
                    // Debug circle showing placement center Arc
                Circle()
                    .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                    .frame(width: arcRadius * 2, height: arcRadius * 2)
                    .position(x: centerX, y: centerY)
                    .accessibilityIdentifier("mainMeterCircle")
                    // dB label placement guide arc (green dashed) dB
                Circle()
                    .stroke(Color.green.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .frame(width: arcRadius * 2.4, height: arcRadius * 2.4)
                    .position(x: centerX, y: centerY)
                    .accessibilityIdentifier("topCircle")
                    // dBFS label placement guide arc (purple dashed)
                Circle()
                    .stroke(Color.purple.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    // Move purple dashing line
                    .frame(width: arcRadius * 1.40, height: arcRadius * 1.70)
                    .position(x: centerX, y: centerY)
                    .accessibilityIdentifier("bottomCircle")
                    // Adjust the arc segments
                ZStack {
                    ArcSegment(startAngle: mapDBToAngle(-20) - 90, endAngle: mapDBToAngle(-2) - 90, radius: tickRadius)
                        .stroke(Color.green, lineWidth: 3)
                    ArcSegment(startAngle: mapDBToAngle(-2) - 90, endAngle: mapDBToAngle(1) - 90, radius: tickRadius)
                        .stroke(Color.yellow, lineWidth: 3)
                    ArcSegment(startAngle: mapDBToAngle(1) - 90, endAngle: mapDBToAngle(3) - 90, radius: tickRadius)
                        .stroke(Color.red, lineWidth: 3)
                }
                .frame(width: arcRadius * 2, height: arcRadius * 2)
                .position(x: centerX, y: centerY)
                
                ForEach(ticks.map { $0.1 }, id: \.self) { value in
                    let angle = Angle(degrees: mapDBToAngle(value) - 90)
                    let x = cos(angle.radians)
                    let y = sin(angle.radians)
                    let debugX = centerX + arcRadius * x
                    let debugY = centerY + arcRadius * y
                    Circle()
                        .fill(Color.red.opacity(0.5))
                        .frame(width: 6, height: 6)
                        .position(x: debugX, y: debugY)
                }
                
                CustomTickMarks(centerX: centerX, centerY: centerY, arcRadius: arcRadius, geometry: geometry)
                
                let leftAngle = angleForLevel(leftLevel)
                
                    // Needle with visible caps at base and tip
                ZStack {
                        // Red needle extending from center
                    Capsule()
                        .fill(Color.red.opacity(leftLevel > 2.0 ? 1.0 : 0.8))
                        .frame(width: 2, height: arcRadius + 20)
                        .offset(y: -(arcRadius + 20) / 2) // Move tip to arc, base to center
                        .rotationEffect(leftAngle)
                        .position(x: centerX, y: centerY)
                    
                        // Center base dot
                    Circle()
                        .fill(Color.black)
                        .frame(width: 8, height: 8)
                        .position(x: centerX, y: centerY)
                }
                .animation(.interpolatingSpring(stiffness: 60, damping: 8), value: leftAngle.degrees)
                
                Text("dB")
                    .font(.subheadline)
                    .foregroundColor(.black)
                    .position(x: centerX, y: centerY - arcRadius * 1.5)
                
                Text("dBFS")
                    .font(.subheadline)
                    .foregroundColor(.black)
                    .position(x: centerX, y: centerY - arcRadius * 0.3)
                
                Text("0 VU = -12 dBFS")
                    .font(.caption2)
                    .foregroundColor(.black.opacity(0.7))
                    .position(x: centerX, y: centerY + arcRadius * 1.25)
            }
            .background(Color(red: 0.96, green: 0.94, blue: 0.86))
            .aspectRatio(contentMode: .fit)
            .frame(width: geometry.size.width, height: geometry.size.width)
     //       .padding(5)
    //.overlay(
   //         Text(label: )
//                    .font(.subheadline.bold())
//                    .foregroundColor(.black.opacity(0.8))
//                    .padding(.top, 110),
//                alignment: .center
 //        )
        }
    }
    
}

    // Move mapDBToAngle to global scope so it can be reused
private let minDB: Float = -20
private let maxDB: Float = 3
private let minAngle: Double = -80
private let maxAngle: Double = 80

func mapDBToAngle(_ db: Float) -> Double {
    let clamped = min(max(db, minDB), maxDB)
    let normalized = Double(clamped - minDB) / Double(maxDB - minDB)
    return minAngle + normalized * (maxAngle - minAngle)
}

let ticks: [((String, String), Float)] = [
    (("-20", "-80"), -20),
    (("-15", "-60"), -15),
    (("-10", "-40"), -10),
    (("-7", "-24"), -7),
    (("-3", "-18"), -3),    // was -2.5
    (("0", "-12"), 0),      // was -0.8
    (("+1", "-6"), 1.1),      // updated from 1.2
    (("+2", "-4"), 2.0),      // updated from 2.2
    (("+3", "-2"), 3.0)      // updated from 3.8
    
]

struct ArcSegment: Shape {
    var startAngle: Double
    var endAngle: Double
    var radius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.width / 2.0, y: rect.height / 2.0)
        path.addArc(center: center,
                    radius: radius,
                    startAngle: Angle(degrees: startAngle),
                    endAngle: Angle(degrees: endAngle),
                    clockwise: false)
        return path
    }
}

private struct CustomTickMarks: View {
    var centerX: CGFloat
    var centerY: CGFloat
    var arcRadius: CGFloat
    var geometry: GeometryProxy
    
    var body: some View {
            // Render dB and dBFS labels and align them to corresponding tick marks along the arc
        ForEach(Array(ticks.enumerated()), id: \.offset) { offset, tick in
            let tickLabelPair = tick.0
            let dbfsValue = tick.1
            let dbLabel = tickLabelPair.0
            let dbfsLabel = tickLabelPair.1
            let angle = Angle(degrees: mapDBToAngle(Float(dbfsValue)) - 90)
            let labelOffset: CGFloat = geometry.size.width * 0.07
            let x = cos(angle.radians)
            let y = sin(angle.radians)
            let tickLength: CGFloat = geometry.size.width * 0.05
            
            let startX = centerX + arcRadius * x
            let startY = centerY + arcRadius * y
            let endX = centerX + (arcRadius - tickLength) * x
            let endY = centerY + ((arcRadius - tickLength) * y)
                // Distance between dB and dbFS values, moved further below tick marks
                /// Positioning the label group (dB/dBFS) on the dBFS guide arc (purple dashed)
            Path { path in
                path.move(to: CGPoint(x: startX, y: startY))
                path.addLine(to: CGPoint(x: endX, y: endY))
            }
         //   .stroke(Color.black, lineWidth: 1.5)

                // Position dB label slightly closer to tick marks
            let dbLabelX = centerX + (arcRadius + labelOffset * 0.9) * x
            let dbLabelY = centerY + (arcRadius + labelOffset * 0.9) * y
            
                // Position dBFS label directly on purple dashed arc (bottomCircle)
                // Offset dbFS label counterclockwise by a small amount for better alignment
            let adjustedAngle = Angle(degrees: mapDBToAngle(Float(dbfsValue)) - 90 - 3)
            let adjustedX = cos(adjustedAngle.radians)
            let adjustedY = sin(adjustedAngle.radians)
            let dbfsLabelX = centerX + (arcRadius * 0.70) * adjustedX
            let dbfsLabelY = centerY + (arcRadius * 0.70) * adjustedY
            
            Text(dbLabel)
                .font(dbLabel.contains("0") ? .system(size: 12, weight: .bold, design: .rounded) : .system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(dbLabel.contains("0") ? .red : .black)
                .rotationEffect(.degrees((angle.degrees > 90 || angle.degrees < -90) ? angle.degrees + 180 : angle.degrees))
                .position(x: dbLabelX, y: dbLabelY)
                // dBFS label placed on purple arc guide for alignment
            Text(dbfsLabel)
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundColor(.purple)
                .rotationEffect(.zero) // Always keep text upright
                .position(x: dbfsLabelX, y: dbfsLabelY)
        }
    }
}

    // MARK: - SwiftUI Preview
#if DEBUG
struct StyledAnalogVUMeterView_Previews: PreviewProvider {
    static var previews: some View {
        StyledAnalogVUMeterView(leftLevel: -6.0, rightLevel: -3.0)
            .frame(width: 280, height: 280)
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
#endif
