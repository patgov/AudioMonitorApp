//
//  AudioMonitorView_Previews.swift
//  AudiioMonitorApp
//
//  Created by Pat Govan on 3/30/25.
//

import SwiftUI

#Preview {
    let processor = AudioProcessor()
    let placeholderLogManager = LogManager(audioManager: nil) // Temporary placeholder
    let audioManager = AudioManager(processor: processor, logManager: placeholderLogManager)
    placeholderLogManager.audioManager = audioManager // Inject audioManager into logManager
    let viewModel = AudioMonitorViewModel(audioManager: audioManager, logManager: placeholderLogManager)

    return AudioMonitorView(viewModel: viewModel)
}
