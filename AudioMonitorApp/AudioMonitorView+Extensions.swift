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
            leftLevel: viewModel.leftLevel,
            rightLevel: viewModel.rightLevel
        )
        .frame(width: 300, height: 150)
        .padding()
        .background(Color.black)
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    AudioMonitorView_Extensions(viewModel: AudioMonitorViewModel.preview)
}
