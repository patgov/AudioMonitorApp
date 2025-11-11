

import SwiftUI

struct VUMeterPreviewWrapper: View {
    @ObservedObject var viewModel: AudioMonitorViewModel
    
    func angleForLevel(_ level: Double) -> Angle {
        let clampedLevel = min(max(level, -60), 0)
        let degrees = (clampedLevel + 20) * (180.0 / 23.0) - 90
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
            meterView(for: viewModel.leftLevel)
            meterView(for: viewModel.rightLevel)
        }
        .frame(height: 250)        .padding()
    }
}

#if DEBUG
#Preview(traits: .sizeThatFitsLayout) {
    VUMeterPreviewWrapper(viewModel: AudioMonitorViewModel.preview)
}
#endif
