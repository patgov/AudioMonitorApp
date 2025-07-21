    // Maps dBFS input (-70...0) to traditional analog VU meter dB scale (-20...+3)
func vuMapped(from dbfs: Float) -> Float {
    let clamped = max(-70, min(dbfs, 0))
    return (clamped + 70) * (23.0 / 70.0) - 20 // Maps -70...0 dBFS to -20...+3 VU dB
}

import SwiftUI

struct VUMeterNeedleView: View {
    var level: Float
    var label: String
    
    private let displayMinDB: Float = -20
    private let displayMaxDB: Float = 3
    
    private func tickMarkView(for db: Float, center: CGPoint, radius: CGFloat, isMajor: Bool = false) -> some View {
        let tickNorm = (db - displayMinDB) / (displayMaxDB - displayMinDB)
        let tickAngle = Angle(degrees: -160 + Double(tickNorm * 140))
        let dx = cos(tickAngle.radians)
        let dy = sin(tickAngle.radians)
        
        let tickLength: CGFloat = isMajor ? 12 : 6
        let tickColor: Color
        if db >= 0 {
            tickColor = .red
        } else if db >= -6 {
            tickColor = .yellow
        } else {
            tickColor = .white
        }
        
        let tickStart = CGPoint(x: center.x + dx * (radius - 10), y: center.y + dy * (radius - 20))
        let tickEnd = CGPoint(x: center.x + dx * (radius - 10 + tickLength), y: center.y + dy * (radius - 20 + tickLength))
        let labelPos = CGPoint(x: center.x + dx * (radius + 16), y: center.y + dy * (radius + 20))
        
        return ZStack {
            Path { path in
                path.move(to: tickStart)
                path.addLine(to: tickEnd)
            }
            .stroke(tickColor, lineWidth: isMajor ? 1.5 : 1)
            
            if isMajor {
                Text(db == 0 ? "0" : String(format: "%+.0f", db))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(tickColor)
                    .position(labelPos)
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let center = CGPoint(x: width / 2, y: height / 2 + height * 0.15)
            let radius = min(width, height) * 0.45
            
            let vuLevel = vuMapped(from: level)
            let clampedLevel = max(displayMinDB, min(vuLevel, displayMaxDB))
            let normalized = (clampedLevel - displayMinDB) / (displayMaxDB - displayMinDB)
            let angle = Angle(degrees: -70 + Double(normalized * 140)) // Shifted -20° for better alignment
            
            let fineTicks = Array(stride(from: displayMinDB, through: displayMaxDB + 0.1, by: 1))
            let majorTickBase = Array(stride(from: displayMinDB, through: displayMaxDB + 0.1, by: 3))
            let extraPositiveTicks: [Float] = [1, 2, 3]
            let majorTicks = Set((majorTickBase + extraPositiveTicks).sorted())
            
                //   DispatchQueue.main.async {
                //       print("🔁 VUMeterNeedleView – level:", level, "clamped:", clampedLevel, "normalized:", normalized)
                //       print("🧭 Needle angle in degrees:", angle.degrees)
                //  }
            
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color.black, Color.gray.opacity(0.7)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                    // Background Arc
                ArcShape(startAngle: .degrees(-165), endAngle: .degrees(10), clockwise: false)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                    .frame(width: radius * 5, height: radius)
                    .offset(y: -radius - 10)
                    .position(center)
                
                    // Tick Marks and Labels
                ZStack {
                    ForEach(fineTicks, id: \.self) { db in
                        tickMarkView(for: db, center: center, radius: radius, isMajor: majorTicks.contains(db))
                    }
                }
                
                    // Needle
                Rectangle()
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [Color(red: 1.0, green: 0.4, blue: 0.0), Color(red: 0.6, green: 0.0, blue: 0.0)]),
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(width: 3, height: radius)
                    .offset(y: -radius / 2)
                    .rotationEffect(angle)
                    .position(x: center.x, y: center.y)
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                    // .rotationEffect(.degrees(-30))
                
                    // Pivot circle
                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.black, lineWidth: 1))
                    .position(center)
                
                    // Label
                Text(label)
                    .font(.caption)
                    .foregroundColor(.white)
                    .position(x: center.x, y: center.y + radius * 0.7)
                
                    // Reflective overlay for glass look
                Rectangle()
                    .fill(LinearGradient(colors: [.white.opacity(0.05), .clear], startPoint: .top, endPoint: .bottom))
                    .blendMode(.screen)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(red: 0.4, green: 0.4, blue: 0.45).opacity(0.85), lineWidth: 1.5)
                    .shadow(radius: 1)
            )
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [Color(red: 0.15, green: 0.15, blue: 0.18), Color(red: 0.05, green: 0.05, blue: 0.08)]),
                        startPoint: .top,
                        endPoint: .bottom)
                    )
            )
        }
    }
}

#Preview {
    TimelineView(.animation) { timeline in
        let now = timeline.date.timeIntervalSinceReferenceDate
        let dynamicLevel = Float(sin(now * 1.5) * 11.5 + -8.5) // sweeps roughly from -20 to +3 dB
        
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color(red: 0.12, green: 0.12, blue: 0.15), .black]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            HStack(spacing: 32) {
                VUMeterNeedleView(level: dynamicLevel, label: "L")
                VUMeterNeedleView(level: dynamicLevel, label: "R")
            }
            .padding()
        }
        .frame(width: 600, height: 300)
    }
}
    // Arc shape for background
struct ArcShape: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var clockwise: Bool
    
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                 radius: rect.height / 2,
                 startAngle: startAngle,
                 endAngle: endAngle,
                 clockwise: clockwise)
        return p
    }
}
