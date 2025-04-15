import SwiftUI

    // AnalogVUMeterView.swift – Stereo Analog VU Wrapper

struct AnalogVUMeterView: View {
    @Binding var leftLevel: Float
    @Binding var rightLevel: Float
    
    var body: some View {
        HStack(spacing: 0) {
            VUMeterNeedleView(level: $leftLevel, label: "L")
            VUMeterNeedleView(level: $rightLevel, label: "R")
        }
        .padding()
        .background(Color.black)
    }
}

struct AnalogVUMeterView_Previews: PreviewProvider {
    struct Container: View {
        @State private var left: Float = 0
        @State private var right: Float = 0
        
        var body: some View {
            AnalogVUMeterView(leftLevel: $left, rightLevel: $right)
                .padding()
                .background(Color.black)
        }
    }
    
    static var previews: some View {
        Container()
            .previewLayout(.sizeThatFits)
    }
}

struct VUMeterNeedleView: View {
    @Binding var level: Float
    var label: String
    
    private let minDB: Float = -80
    private let maxDB: Float = 0
    private let minAngle: Double = -50
    private let maxAngle: Double = 50
    
    var clampedAngle: Angle {
        let clamped = min(max(level, minDB), maxDB)
        let normalized = Double(clamped - minDB) / Double(maxDB - minDB)
        let degrees = minAngle + normalized * (maxAngle - minAngle)
        print("📐 \(label) dB: \(level), angle: \(degrees)")
        return Angle(degrees: degrees)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                VUMeterArcRange(start: -20, end: -3)
                    .stroke(Color.green, lineWidth: 6)
                VUMeterArcRange(start: -3, end: 0)
                    .stroke(Color.yellow, lineWidth: 6)
                VUMeterArcRange(start: 0, end: 3)
                    .stroke(Color.white, lineWidth: 6)
                VUMeterArcRange(start: 3, end: 7)
                    .stroke(Color.red, lineWidth: 6)
                
                VUMeterArc()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                
                VUMeterScale()
                    .stroke(Color.white, lineWidth: 1)
                
                VUScaleTicks()
                    .stroke(Color.yellow.opacity(0.7), lineWidth: 1)
                
                Needle(angle: clampedAngle)
                    .stroke(Color.red, lineWidth: 2)
                
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
            }
            .frame(width: 120, height: 80)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.white)
        }
    }
}

struct VUMeterNeedleView_Previews: PreviewProvider {
    struct Container: View {
        @State private var testLevel: Float = -3
        
        var body: some View {
            VUMeterNeedleView(level: $testLevel, label: "Preview")
                .padding()
                .background(Color.black)
        }
    }
    
    static var previews: some View {
        Container()
            .previewLayout(.sizeThatFits)
    }
}

struct VUMeterArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2 * 0.9
        let center = CGPoint(x: rect.midX, y: rect.midY)
        
        path.addArc(center: center,
                    radius: radius,
                    startAngle: .degrees(-50),
                    endAngle: .degrees(50),
                    clockwise: false)
        return path
    }
}

    // Testing code below

struct Needle: Shape {
    var angle: Angle
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let length = rect.width * 0.4
        
        let radians = angle.radians
        let tip = CGPoint(
            x: center.x + Foundation.cos(radians) * length,
            y: center.y + Foundation.sin(radians) * length
        )
        
        path.move(to: center)
        path.addLine(to: tip)
        
        return path
    }
}

struct VUScaleTicks: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width * 0.45
        
        let tickCount = 14
        for i in 0..<tickCount {
            let fraction = Double(i) / Double(tickCount - 1)
            let angle = Angle.degrees(-50 + fraction * 100).radians
            let inner = CGPoint(
                x: center.x + Foundation.cos(angle) * (radius - 8),
                y: center.y + Foundation.sin(angle) * (radius - 8)
            )
            let outer = CGPoint(
                x: center.x + Foundation.cos(angle) * radius,
                y: center.y + Foundation.sin(angle) * radius
            )
            path.move(to: inner)
            path.addLine(to: outer)
        }
        
        return path
    }
}

struct VUMeterScale: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width * 0.4
        
        let ticks: [(Double, String?)] = [(-20.0, "-20"), (0.0, "0"), (7.0, "+7")]
        
        for (dB, label) in ticks {
            let angle = Angle.degrees(-50 + (100 * ((dB + 20) / 27.0)))
            let tickStart = CGPoint(
                x: center.x + radius * Foundation.cos(angle.radians),
                y: center.y + radius * Foundation.sin(angle.radians)
            )
            let tickEnd = CGPoint(
                x: center.x + (radius - 10) * Foundation.cos(angle.radians),
                y: center.y + (radius - 10) * Foundation.sin(angle.radians)
            )
            
            path.move(to: tickStart)
            path.addLine(to: tickEnd)
            
            if let label = label {
                let labelPosition = CGPoint(
                    x: center.x + (radius - 20) * Foundation.cos(angle.radians),
                    y: center.y + (radius - 20) * Foundation.sin(angle.radians)
                )
                path.addRect(CGRect(x: labelPosition.x, y: labelPosition.y, width: 20, height: 10))
            }
        }
        
        return path
    }
}

struct VUMeterArcRange: Shape {
    let start: Double
    let end: Double
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 * 0.9
        let startAngle = Angle(degrees: -50 + 100 * ((start + 20) / 27.0))
        let endAngle = Angle(degrees: -50 + 100 * ((end + 20) / 27.0))
        
        path.addArc(center: center, radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: false)
        return path
    }
}
