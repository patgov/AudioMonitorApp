    //
    //  AudioWarningView.swift
    //  AudioMonitorApp
    //
    //  Created by Pat Govan on 6/8/25.
    //

import SwiftUI

struct AudioWarningView: View {
    @Binding var isVisible: Bool
    var warningMessage: String = "⚠️ No audio input detected"
    
    var body: some View {
        if isVisible {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.largeTitle)
                Text(warningMessage)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                    .padding()
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            .cornerRadius(12)
            .shadow(radius: 4)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: isVisible)
        }
    }
}

#Preview("WarningView", traits: .sizeThatFitsLayout) {
    AudioWarningView(isVisible: .constant(true), warningMessage: "⚠️ No audio signal detected on input device")
}
