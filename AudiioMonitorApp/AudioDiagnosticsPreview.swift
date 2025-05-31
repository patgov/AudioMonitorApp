import SwiftUI

struct AudioDiagnosticsPreview: PreviewProvider {
    static var previews: some View {
        AudioDiagnosticsView(stats: .init(left: -20.0, right: -1.0, inputName: "Preview Mic", inputID: 1))
    }
}
