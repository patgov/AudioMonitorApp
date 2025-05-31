import SwiftUI

struct VUMeterPreviewWrapper: View {
    var leftLevel: Float
    var rightLevel: Float

    var body: some View {
        HStack(spacing: 40) {
            StyledAnalogVUMeterView(leftLevel: leftLevel, rightLevel: rightLevel)
                .frame(width: 280, height: 280)
            StyledAnalogVUMeterView(leftLevel: leftLevel, rightLevel: rightLevel)
                .frame(width: 280, height: 280)
        }
    }
}

#if DEBUG
struct VUMeterPreviewWrapper_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            VUMeterPreviewWrapper(leftLevel: -10.0, rightLevel: -10.0)
        }
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
#endif

