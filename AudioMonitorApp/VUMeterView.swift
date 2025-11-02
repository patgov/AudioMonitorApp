    //  VUMeterView.swift
    //  AudioMonitorApp
    // dual needle-style VU meters for left and right channels,
    // including smooth animation and labeled indicators.
    //


import SwiftUI

struct VUMeterNeedle: View {
    var level: Float  // expected to be from -80.0 to 0.0 or +6.0
    
    var clampedLevel: CGFloat {
        CGFloat(max(min(level, 6), -80))
    }
    
    var needleAngle: Angle {
            // Map from -80...6 dB to a 270º sweep (-135º to +135º)
        let normalized = (clampedLevel + 80) / 86
        return Angle(degrees: Double(normalized * 270) - 135)
    }
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 2)
                .opacity(0.2)
            
            NeedleShape()
                .stroke(Color.red, lineWidth: 2)
                .frame(width: 2, height: 40)
                .offset(y: -20)
                .rotationEffect(needleAngle)
                .animation(.interpolatingSpring(stiffness: 200, damping: 20), value: needleAngle)
        }
        .frame(width: 60, height: 60)
    }
}

struct NeedleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        return path
    }
}

#Preview {
    VUMeterNeedle(level: 0.0)
}
