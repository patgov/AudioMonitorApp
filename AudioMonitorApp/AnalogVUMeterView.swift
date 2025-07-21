import SwiftUI

struct AnalogVUMeterView: View {
    @Binding var leftLevel: Float
    @Binding var rightLevel: Float

    var body: some View {
        GeometryReader { geometry in
            VStack {
                Text("Stereo VU Meter")
                    .font(.title3.bold())
                    .foregroundColor(.yellow)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 8)

                HStack(spacing: 32) {
                    VStack {
                        VUMeterNeedleView(level: leftLevel, label: "L")
                            .frame(width: geometry.size.width * 0.4, height: geometry.size.width * 0.4)
                        Text(String(format: "%.1f dB", leftLevel))
                            .foregroundColor(.green)
                            .font(.caption2)
                    }
                    .layoutPriority(1)

                    VStack {
                        VUMeterNeedleView(level: rightLevel, label: "R")
                            .frame(width: geometry.size.width * 0.4, height: geometry.size.width * 0.4)
                        Text(String(format: "%.1f dB", rightLevel))
                            .foregroundColor(.green)
                            .font(.caption2)
                    }
                    .layoutPriority(1)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
            .background(Color(red: 0.96, green: 0.94, blue: 0.86))            }
          //  .padding(.top, 80)
        }
    }
}
#Preview("Analog VU Meter Preview", traits: .sizeThatFitsLayout) {
    AnalogVUMeterView(
        leftLevel: .constant(-80.0),
        rightLevel: .constant(-80.0)
    )
    .frame(maxWidth: .infinity, minHeight: 300)
    .padding()
    .background(Color.black)
}


struct AnalogVUMeterView_Previews {
    struct Container: View {
        @State private var left: Float = -80
        @State private var right: Float = -80

        var body: some View {
            AnalogVUMeterView(leftLevel: $left, rightLevel: $right)
                .padding()
                .background(Color.black)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        left = 6.5
                        right = 6.5
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            left = -80
                            right = -80
                        }
                    }
                }
        }
    }

    static var previews: some View {
        Container()
            .frame(maxWidth: .infinity, minHeight: 300)
            .background(Color.black)
            .previewLayout(.device)
    }
}

//
//struct VUMeterNeedleView_Previews: PreviewProvider {
//    struct Container: View {
//        @State private var testLevel: Float = -80
//
//        var body: some View {
//            VUMeterNeedleView(level: testLevel, label: "Preview")
//                .padding()
//             //   .background(Color.black)
//        }
//    }
//
//    static var previews: some View {
//        Container()
//            .previewLayout(.sizeThatFits)
//    }
//}
