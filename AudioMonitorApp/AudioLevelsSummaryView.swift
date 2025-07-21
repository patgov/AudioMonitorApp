    //
    //  AudioLevelsSummaryView.swift
    //  AudioMonitorApp
    //
    //  Created by Pat Govan on 6/8/25.
    //

import SwiftUI

struct AudioLevelsSummaryView: View {
    var leftText: String
    var rightText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Audio Level Summary")
                .font(.headline)
            HStack {
                Text("Left: \(leftText) dB")
                Spacer()
                Text("Right: \(rightText) dB")
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .padding()
    }
}

#Preview {
    AudioLevelsSummaryView(leftText: "-22.4", rightText: "-19.7")
}
