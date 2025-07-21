import SwiftUI

struct VUMeterPreviewWrapper: View {
    var leftLevel: Double
    var rightLevel: Double
    
    func angleForLevel(_ level: Double) -> Angle {
        let clampedLevel = min(max(level, -60), 0)
        let degrees = (clampedLevel + 60) * 2 - 60
        return Angle(degrees: degrees)
    }
    
    func meterView(for level: Double) -> some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let angle = angleForLevel(level)
            
            ZStack {
                Image("VUBackground")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                
                Image("VUGraphics")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                
                Image("VUNeedle")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .rotationEffect(angle)
                    .animation(.interpolatingSpring(stiffness: 60, damping: 8), value: angle)
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 40) {
            meterView(for: leftLevel)
            meterView(for: rightLevel)
        }
        .frame(height: 250)
        .padding()
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    VUMeterPreviewWrapper(leftLevel: -12.0, rightLevel: -6.0)
}
