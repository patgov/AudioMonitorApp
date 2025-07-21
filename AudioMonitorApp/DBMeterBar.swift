//
//  DBMeterBar.swift
//  AudiioMonitorApp
//
//  Created by Pat Govan on 5/7/25.
//

import SwiftUI

struct DBMeterBar: View {
    var value: Float
    var label: String

    var body: some View {
        VStack {
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    Capsule()
                        .frame(width: 12)
                        .foregroundColor(Color.gray.opacity(0.2))

                    Capsule()
                        .frame(width: 12, height: barHeight(in: geometry.size.height))
                        .foregroundColor(barColor)
                        .animation(.easeInOut(duration: 0.2), value: value)
                }
            }
            .frame(height: 100)

            Text(label)
                .font(.caption)
        }
    }

    private func barHeight(in totalHeight: CGFloat) -> CGFloat {
        let clampedValue = max(-80, min(0, value))
        return totalHeight * CGFloat((clampedValue + 80) / 80)
    }

    private var barColor: Color {
        switch value {
            case ..<(-40): return .blue
            case -40..<(-10): return .green
            case -10..<(-2): return .yellow
            default: return .red
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    VStack(spacing: 16) {
        DBMeterBar(value: -60, label: "L")
        DBMeterBar(value: -10, label: "R")
        DBMeterBar(value: 0, label: "CLIP")
    }
    .padding()
}
