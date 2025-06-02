import SwiftUI

struct VUMeterPreviewWrapper: View {
    var leftLevel: Float
    var rightLevel: Float

    var body: some View {
        HStack(spacing: 40) {
            ZStack {
                StyledAnalogVUMeterView(leftLevel: leftLevel, rightLevel: rightLevel)
                    .frame(width: 280, height: 280)

                    .overlay(
                        Text("L" )
                            .font(.subheadline.bold())
                            .foregroundColor(.black.opacity(0.8))
                            .padding(.top, 110),
                        alignment: .center
                    )

            }


                StyledAnalogVUMeterView(leftLevel: leftLevel, rightLevel: rightLevel)
                    .frame(width: 280, height: 280)

                    .overlay(
                             Text("R" )
                                        .font(.subheadline.bold())
                                        .foregroundColor(.black.opacity(0.8))
                                        .padding(.top, 110),
                                    alignment: .center
                            )

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

