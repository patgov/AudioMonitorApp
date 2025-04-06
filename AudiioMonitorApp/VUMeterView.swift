//    //
//    //  VUMeterView.swift
//    //  AudioMonitorApp
//    //
//
///*
// dual needle-style VU meters for left and right channels,
// including smooth animation and labeled indicators.
//
//*/
//
//import SwiftUI
//
//struct VUMeterNeedle: View {
//    var level: Float  // expected to be from -80.0 to 0.0 or +6.0
//
//    var clampedLevel: CGFloat {
//        CGFloat(max(min(level, 6), -80))
//    }
//
//    var needleAngle: Angle {
//            // Map from -80...6 dB to a 270º sweep (-135º to +135º)
//        let normalized = (clampedLevel + 80) / 86
//        return Angle(degrees: Double(normalized * 270) - 135)
//    }
//
//    var body: some View {
//        ZStack {
//            Circle()
//                .stroke(lineWidth: 2)
//                .opacity(0.2)
//
//            Rectangle()
//                .fill(Color.red)
//                .frame(width: 2, height: 40)
//                .offset(y: -20)
//                .rotationEffect(needleAngle)
//                .animation(.easeOut(duration: 0.1), value: level)
//        }
//        .frame(width: 60, height: 60)
//    }
//}
//struct MeterNeedleView: View {
//    let label: String
//    let level: Float
//
//    var angle: Angle {
//            // Map level 0.0 - 1.0 to -50 to +50 degrees
//        let clampedLevel = max(0.0, min(level, 1.0))
//        return Angle(degrees: Double(clampedLevel) * 100.0 - 50.0)
//    }
//
//    var body: some View {
//        ZStack {
//            Circle()
//                .stroke(lineWidth: 2)
//                .foregroundColor(.gray)
//
//            NeedleShape()
//                .fill(Color.red)
//                .frame(width: 2, height: 40)
//                .offset(y: -20)
//                .rotationEffect(angle)
//                .animation(.easeOut(duration: 0.1), value: angle)
//
//            Text(label)
//                .font(.caption)
//                .bold()
//                .offset(y: 35)
//        }
//        .frame(width: 80, height: 80)
//    }
//}
//
//struct NeedleShape: Shape {
//    func path(in rect: CGRect) -> Path {
//        var path = Path()
//        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
//        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
//        return path
//    }
//}
//
//#Preview {
//    VUMeterNeedle(level: 0.0)
//}
