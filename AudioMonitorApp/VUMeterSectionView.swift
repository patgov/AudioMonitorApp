    //
    //  VUMeterSectionView.swift
    //  AudioMonitorApp
    //
    //  Created by Pat Govan on 6/8/25.
    //

import SwiftUI

struct VUMeterSectionView: View {
    var leftLevel: Float
    var rightLevel: Float
    
    var body: some View {
        VStack {
            Text("Stereo VU Meter")
                .font(.headline)
                .padding(.top)
            
            HStack(spacing: 20) {
                VStack {
                    StyledAnalogVUMeterView(leftLevel: leftLevel, rightLevel: leftLevel)
                        .frame(width: 140, height: 150)
                    Text("L")
                        .font(.caption)
                }
                VStack {
                    StyledAnalogVUMeterView(leftLevel: rightLevel, rightLevel: rightLevel)
                        .frame(width: 140, height: 150)
                    Text("R")
                        .font(.caption)
                }
            }
        }
        .padding()
    }
}

#Preview {
    VUMeterSectionView(leftLevel: 0.65, rightLevel: 0.65)
}
