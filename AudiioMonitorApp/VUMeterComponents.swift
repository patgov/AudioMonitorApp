import SwiftUI

///Needle
struct Needle: Shape {
    var angle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let length = min(rect.width, rect.height) * 0.45
        let end = CGPoint(
            x: center.x + cos(CGFloat(angle.radians)) * length,
            y: center.y + sin(CGFloat(angle.radians)) * length
        )
        path.move(to: center)
        path.addLine(to: end)
        return path
    }
}

///VUScaleTicks
struct VUScaleTicks: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.48

        for db in stride(from: -20, through: 7, by: 1) {
            let normalized = Double(db + 20) / 27.0
            let angle = Angle(degrees: -50 + (100 * normalized)).radians
            let tickStart = CGPoint(
                x: center.x + cos(CGFloat(angle)) * radius,
                y: center.y + sin(CGFloat(angle)) * radius
            )
            let tickEnd = CGPoint(
                x: center.x + cos(CGFloat(angle)) * radius,
                y: center.y + sin(CGFloat(angle)) * radius
            )
            path.move(to: tickStart)
            path.addLine(to: tickEnd)
        }

        return path
    }
}

///VuMeterArc
struct VUMeterArc: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) * 0.45
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let startAngle = Angle(degrees: -50)
        let endAngle = Angle(degrees: 50)

        return Path { path in
            path.addArc(center: center,
                        radius: radius,
                        startAngle: startAngle,
                        endAngle: endAngle,
                        clockwise: false)
        }
    }
}

///VUMeterArcRange
struct VUMeterArcRange: Shape {
    let start: Double
    let end: Double

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) * 0.45
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let startAngle = Angle(degrees: -50 + (100 * ((start + 20) / 27.0)))
        let endAngle = Angle(degrees: -50 + (100 * ((end + 20) / 27.0)))

        return Path { path in
            path.addArc(center: center,
                        radius: radius,
                        startAngle: startAngle,
                        endAngle: endAngle,
                        clockwise: false)
        }
    }
}

/// VUMeterScale
struct VUMeterScale: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.46

        for db in stride(from: -20, through: 7, by: 1) {
            let normalized = Double(db + 20) / 27.0
            let angle = Angle(degrees: -50 + (100 * normalized)).radians

            let tickLength: CGFloat = db.isMultiple(of: 5) ? 8 : 4
            let innerRadius = radius - tickLength

            let start = CGPoint(
                x: center.x + cos(CGFloat(angle)) * innerRadius,
                y: center.y + sin(CGFloat(angle)) * innerRadius
            )
            let end = CGPoint(
                x: center.x + cos(CGFloat(angle)) * radius,
                y: center.y + sin(CGFloat(angle)) * radius
            )

            path.move(to: start)
            path.addLine(to: end)
        }

        return path
    }
}
