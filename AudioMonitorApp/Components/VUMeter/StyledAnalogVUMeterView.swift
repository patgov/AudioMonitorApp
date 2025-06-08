    //
    //  Created by Pat Govan on 6/8/25.
    //
    /// StyledAnalogVUMeterView.swift
    /// AudioMonitorApp
    ///
    /// This file defines a vintage-styled analog VU meter SwiftUI view.
    /// It displays an animated needle indicating real-time audio levels in dBFS,
    /// using a -20 to +7 dB scale mapped to angles on a 120° arc.
    ///
    /// Includes:
    /// - Custom tick mark rendering (label, position, angle)
    /// - Arc segments color-coded for dB thresholds
    /// - Animated needle based on real-time dB input
    /// - Visual refinements styled after 1950s/1970s broadcast equipment

import SwiftUI
import AVFoundation
import Combine


    /// Helper to map dBFS ticks to VU dB ticks for arc positioning
func findCorrespondingDBTick(for dbfs: Double) -> Double {
        // Linear mapping: -33...0 dBFS → -20...+7 dB
    let dbfsMin = -33.0, dbfsMax = 0.0
    let dbMin = -20.0, dbMax = 7.0
    let normalized = (dbfs - dbfsMin) / (dbfsMax - dbfsMin)
    return dbMin + normalized * (dbMax - dbMin)
}

    /// Maps a VU dB tick value (–20 to +7 dB) back to its corresponding dBFS value
func mapVUToDBFS(_ vuDB: Double) -> Double {
        // Reverse of findCorrespondingDBTick
    let dbMin = -20.0, dbMax = 7.0
    let dbfsMin = -33.0, dbfsMax = -12.0
    let normalized = (vuDB - dbMin) / (dbMax - dbMin)
    return dbfsMin + normalized * (dbfsMax - dbfsMin)
}

    /// Defines the dB labels and corresponding values to render around the VU arc
let ticks: [(label: String, value: Double, isDBFS: Bool)] = [
    ("-33", -33, true), ("-30", -30, true), ("-27", -27, true), ("-24", -24, true),
    ("-20", -21.7, false), ("-18", -18, true), ("-15", -15, false), ("-13", -13, true),
    ("-12", -12, true), ("-10", -10, false), ("-9", -9, true),
    ("-7", -7, false), ("-6", -6, true),
    ("-5", -5, false), ("-3", -3, false), ("-1", -1, false),
    ("0", 0, false), ("+1", 1, false), ("+3", 3, false),
    ("+5", 5, false), ("+7", 7, false)
]


    /// Converts a dB value to a corresponding angle on the VU meter arc
    /// Supports values from -20 to +7 dB
func mapDBToAngle(_ dB: Double) -> Double {
        // Map range: -20 dB to +7 dB → -60° to +60°
    let minDB: Double = -20
    let maxDB: Double = 7
    let minAngle: Double = -60
    let maxAngle: Double = 60

    let clampedDB = min(max(dB, minDB), maxDB)
    let normalized = (clampedDB - minDB) / (maxDB - minDB)
    return minAngle + normalized * (maxAngle - minAngle)
}

    /// Wraps mapDBToAngle to return a SwiftUI `Angle` for needle rotation
func angleForLevel(_ dBLevel: Double) -> Angle {
    Angle(degrees: mapDBToAngle(dBLevel))
}

    /// SwiftUI view to draw labeled dB tick marks around the arc
    /// Uses geometry and trigonometry to position each label
struct CustomTickMarks: View {
    let centerX: CGFloat
    let centerY: CGFloat
    let arcRadius: CGFloat
    let geometry: GeometryProxy


        /// Defines the dB labels and corresponding values to render around the VU arc
    let ticks: [(label: String, value: Double, isDBFS: Bool)] = [
        ("-33", -33, true), ("-30", -30, true), ("-27", -27, true), ("-24", -24, true),
        ("-20", -21.7, false), ("-18", -18, true),
        ("-15", -15, false), ("-13", -13, true),
        ("-12", -12, true), ("-10", -10, false), ("-9", -9, true),
        ("-7", -7, false), ("-6", -6, true),
        ("-5", -5, false), ("-3", -3, false), ("-1", -1, false),
        ("0", 0, false), ("+1", 1, false), ("+3", 3, false),
        ("+5", 5, false), ("+7", 7, false)
    ]

    var body: some View {
        ForEach(ticks, id: \.value) { tick in
            let angle = Angle(degrees: mapDBToAngle(tick.value) - 90)
            let baseTickX = centerX + (arcRadius + 12) * CGFloat(cos(angle.radians))
            let baseTickY = centerY + (arcRadius + 12) * CGFloat(sin(angle.radians))
            Text(tick.label)
                .font(.caption2)
                .foregroundColor(tick.isDBFS ? .gray : .black)
                .position(
                    x: tick.isDBFS ? baseTickX + 6 : baseTickX,
                    y: tick.isDBFS ? baseTickY - 6 : baseTickY
                )
                .rotationEffect(.degrees(mapDBToAngle(tick.value)))
        }
    }
}

    /// SwiftUI view representing a vintage analog-style VU meter
    /// - Uses binding `leftLevel` to reflect the current dB level in real time
    /// - Renders arc, tick marks, and animated needle
struct StyledAnalogVUMeterView: View {
    @Binding var leftLevel: Double

    private func vuMeterBody(geometry: GeometryProxy) -> some View {
        let arcRadius: CGFloat = geometry.size.width * 0.35
        let centerX = geometry.size.width / 2.0
        let centerY = geometry.size.height * 0.5
        let tickRadius = arcRadius

        return ZStack {
                // Colored Arc Segments
            ArcSegment(startAngle: mapDBToAngle(-33) - 90, endAngle: mapDBToAngle(-12) - 90, radius: tickRadius)
                .stroke(Color.gray.opacity(0.3), lineWidth: 4)
            ArcSegment(startAngle: mapDBToAngle(-12) - 90, endAngle: mapDBToAngle(-6) - 90, radius: tickRadius)
                .stroke(Color.orange.opacity(0.4), lineWidth: 4)
            ArcSegment(startAngle: mapDBToAngle(-6) - 90, endAngle: mapDBToAngle(0) - 90, radius: tickRadius)
                .stroke(Color.green.opacity(0.4), lineWidth: 4)
            ArcSegment(startAngle: mapDBToAngle(0) - 90, endAngle: mapDBToAngle(7) - 90, radius: tickRadius)
                .stroke(Color.red.opacity(0.4), lineWidth: 4)

                // Tick Marks
                // Render non-DBFS ticks (VU range) above the arc
            ForEach(ticks.filter { !$0.isDBFS }, id: \.value) { tick in
                let angle = Angle(degrees: mapDBToAngle(tick.value) - 90)
                let tickX = centerX + (tickRadius + 10) * CGFloat(cos(angle.radians))
                let tickY = centerY + (tickRadius + 10) * CGFloat(sin(angle.radians))
                Text(tick.label)
                    .font(.caption2)
                    .foregroundColor(.black)
                    .position(x: tickX, y: tickY)
                    .rotationEffect(.degrees(mapDBToAngle(tick.value)))
            }
                // Render corresponding dBFS ticks (gray) only for pointer dB values (all)
            let vuTicks = ticks.filter { !$0.isDBFS }
            ForEach(Array(vuTicks.enumerated()), id: \.offset) { index, tick in
                let angle = Angle(degrees: mapDBToAngle(tick.value - 2.5) - 90)
                let dbfsValue = mapVUToDBFS(tick.value)
                Text(String(format: "%.0f", dbfsValue))
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .rotationEffect(.degrees(mapDBToAngle(tick.value)))
                    .position(
                        x: centerX + (tickRadius - 14) * CGFloat(cos(angle.radians)),
                        y: centerY + (tickRadius - 14) * CGFloat(sin(angle.radians))
                    )
            }
                // -33 dBFS under -20 dB
            let referenceAngle = Angle(degrees: mapDBToAngle(-20) - 90)
            Text("-33")
                .font(.caption2)
                .foregroundColor(.gray)
                .rotationEffect(.degrees(mapDBToAngle(-20)))
                .position(
                    x: centerX + (tickRadius - 14) * CGFloat(cos(referenceAngle.radians)),
                    y: centerY + (tickRadius - 14) * CGFloat(sin(referenceAngle.radians))
                )
                // Render corresponding dBFS ticks (gray) only for every other pointer dB value (was previously outside)
            ForEach(Array(vuTicks.enumerated()).filter { $0.offset.isMultiple(of: 2) }, id: \.offset) { index, tick in
                let angle = Angle(degrees: mapDBToAngle(tick.value) - 90)
                let dbfsValue = mapVUToDBFS(tick.value)
                let adjustedAngle = Angle(degrees: mapDBToAngle(tick.value - 2.5) - 90)
                Text(String(format: "%.0f", dbfsValue))
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .rotationEffect(.degrees(mapDBToAngle(tick.value)))
                    .position(
                        x: centerX + (tickRadius - 14) * CGFloat(cos(adjustedAngle.radians)),
                        y: centerY + (tickRadius - 14) * CGFloat(sin(adjustedAngle.radians))
                    )
            }

                // Highlight 0 dBFS with a red dot
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .position(
                    x: centerX + (tickRadius - 12) * CGFloat(cos(mapDBToAngle(findCorrespondingDBTick(for: 0)) * .pi / 180 - .pi / 2)),
                    y: centerY + (tickRadius - 12) * CGFloat(sin(mapDBToAngle(findCorrespondingDBTick(for: 0)) * .pi / 180 - .pi / 2))
                )

                // Guide arc for VU dB scale (inner arc)
            ArcSegment(startAngle: 0, endAngle: 360, radius: tickRadius + 5)
                .stroke(Color.black.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3]))
                .zIndex(-1)

                // Guide arc for dBFS scale (moved inside the main arc by 8 points)
            ArcSegment(startAngle: 0, endAngle: 360, radius: tickRadius - 10)
                .stroke(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3]))
                .zIndex(-1)

                // Colored Guide Arcs for Arc Segments
            ArcSegment(startAngle: mapDBToAngle(-33) - 90, endAngle: mapDBToAngle(-12) - 90, radius: tickRadius + 10)
                .stroke(Color.blue.opacity(0.2), style: StrokeStyle(lineWidth: 2, dash: [4]))
            ArcSegment(startAngle: mapDBToAngle(-12) - 90, endAngle: mapDBToAngle(-6) - 90, radius: tickRadius + 10)
                .stroke(Color.orange.opacity(0.2), style: StrokeStyle(lineWidth: 2, dash: [4]))
            ArcSegment(startAngle: mapDBToAngle(-6) - 90, endAngle: mapDBToAngle(0) - 90, radius: tickRadius + 10)
                .stroke(Color.green.opacity(0.2), style: StrokeStyle(lineWidth: 2, dash: [4]))
            ArcSegment(startAngle: mapDBToAngle(0) - 90, endAngle: mapDBToAngle(7) - 90, radius: tickRadius + 10)
                .stroke(Color.red.opacity(0.2), style: StrokeStyle(lineWidth: 2, dash: [4]))

                // Needle
            let needleAngle = angleForLevel(leftLevel)
            let needleLength = arcRadius - 10
            let needleTip = CGPoint(
                x: centerX + CGFloat(cos(needleAngle.radians)) * needleLength,
                y: centerY + CGFloat(sin(needleAngle.radians)) * needleLength
            )
            Path { path in
                path.move(to: CGPoint(x: centerX, y: centerY))
                path.addLine(to: needleTip)
            }
            .stroke(Color.black, lineWidth: 2)
            .shadow(color: Color.black.opacity(0.4), radius: 2, x: 1, y: 1)

            Circle()
                .fill(Color.black)
                .frame(width: 10, height: 10)
                .position(x: centerX, y: centerY)

                // Label
            VStack(spacing: 3) {
                Text("VU Meter")
                    .font(.headline)
                    .foregroundColor(.black)
                Text("Hybrid: –33 dBFS to 0 dBFS | –20 to +7 dB VU")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .position(x: centerX, y: centerY + arcRadius * 1.2)
        }
    }

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                vuMeterBody(geometry: geometry)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.96, green: 0.94, blue: 0.86))
        .aspectRatio(contentMode: .fit)
        .padding(16)
    }
}

struct AnimatedPreviewWrapper: View {
    @State private var level: Double = -20.0
    var timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        StyledAnalogVUMeterView(leftLevel: $level)
            .frame(width: 300, height: 300)
            .onReceive(timer) { _ in
                let next = Double.random(in: -20...7)
                withAnimation(.easeInOut(duration: 0.1)) {
                    level = next
                }
            }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    AnimatedPreviewWrapper()
        .frame(width: 300, height: 300)
}
