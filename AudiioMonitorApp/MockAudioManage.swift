//
//  MockAudioManage.swift
//  AudiioMonitorApp
//
//  Created by Pat Govan on 4/3/25.
//

import Foundation
import Combine

import Foundation
import Combine

class MockAudioManager: AudioManager {
    override init(processor: AudioProcessor, logManager: LogManager) {
        super.init(processor: processor, logManager: logManager)

            // Simulate mock audio levels
        simulateLevels()
    }

    private func simulateLevels() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            let left = Float.random(in: -60...0)
            let right = Float.random(in: -60...0)

            DispatchQueue.main.async {
                self.processor.leftLevel = left
                self.processor.rightLevel = right
                self.processor.isSilent = left < -50 && right < -50
                self.processor.isOvermodulated = left > -2 || right > -2
            }
        }
    }

    override func start() {
        print("🧪 MockAudioManager started")
    }

    override func stop() {
        print("🧪 MockAudioManager stopped")
    }
}
