//
//  AudioMonitorView_Previews.swift
//  AudiioMonitorApp
//
//  Created by Pat Govan on 3/30/25.
//

import SwiftUI

struct AudioMonitorView_Previews: PreviewProvider {
    static var previews: some View {
        AudioMonitorView()
            .environmentObject(AudioProcessor())
    }
}
