    //
    //  ArcSegment.swift
    //  AudioMonitorApp
    //
    //  Created by Pat Govan on 6/8/25.
    //

import SwiftUI

    /// A Shape that renders a circular arc from startAngle to endAngle with a given radius.
struct ArcSegment: Shape {
    var startAngle: Double
    var endAngle: Double
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)

        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(endAngle),
            clockwise: false
        )

        return path
    }
}

#Preview {
    ArcSegment(startAngle: -60, endAngle: 60, radius: 100)
        .stroke(Color.blue, lineWidth: 4)
        .frame(width: 200, height: 200)
}
