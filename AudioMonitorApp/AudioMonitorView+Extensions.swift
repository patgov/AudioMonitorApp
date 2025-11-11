    //
    //  AudioMonitorView+Extensions.swift
    //  AudioMonitorApp
    //
    //  Created by Pat Govan on 6/8/25.
    //

import SwiftUI

struct AudioMonitorView_Extensions: View {
    @ObservedObject var viewModel: AudioMonitorViewModel
    
    var body: some View {
        StyledAnalogVUMeterView(
            leftLevel: Float(viewModel.leftLevel),
            rightLevel: Float(viewModel.rightLevel)
        )
        .frame(width: 300, height: 150)
        .padding()
        .background(Color.black)
    }
}

#if DEBUG
#Preview(traits: .sizeThatFitsLayout) {
    AudioMonitorView_Extensions(viewModel: AudioMonitorViewModel.preview)
}
#endif
