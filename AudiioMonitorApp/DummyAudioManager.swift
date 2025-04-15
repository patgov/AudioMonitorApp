    //
    //  DummyAudioManager.swift
    //  AudiioMonitorApp
    //
    //  Created by Pat Govan on 4/7/25.
    // mimic key behaviors of the real AudioManager.
/*
 •    Inherits from AudioManager.
 •    Overrides start() and stop() to simulate audio levels without needing real input.
 •    Is ideal for SwiftUI previews of VU meters and logging UIs.
 */

import Foundation
import Combine
import AVFoundation

class DummyAudioManager: AudioManager {
    override init(processor: AudioProcessor = AudioProcessor(), logManager: LogManager? = LogManager(audioManager: nil)) {
        super.init(processor: processor, logManager: logManager)
    }
    
    override func start() {
            // Simulate constant audio levels for previews
        processor.leftLevel = -20.0
        processor.rightLevel = -18.0
        processor.isSilent = false
        processor.isOvermodulated = false
    }
    
    override func stop() {
        processor.leftLevel = -80.0
        processor.rightLevel = -80.0
        processor.isSilent = true
        processor.isOvermodulated = false
    }
}
