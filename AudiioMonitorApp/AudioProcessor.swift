import Foundation
import AVFoundation
import Accelerate

class AudioProcessor: ObservableObject {
    @Published var leftLevel: Float = -80.0
    @Published var rightLevel: Float = -80.0
    @Published var isSilent: Bool = false
    @Published var isOvermodulated: Bool = false
    
    private let silenceThreshold: Float = -50.0
    private let overmodulationThreshold: Float = -2.0
    
    func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        print("✅ AudioProcessor received buffer with frame length: \(buffer.frameLength)")
        let frameCount = Int(buffer.frameLength)
        
        let left = calculateLevel(from: channelData[0], count: frameCount)
        let right = buffer.format.channelCount > 1
        ? calculateLevel(from: channelData[1], count: frameCount)
        : left
        
        print("📈 dB Levels — Left: \(left), Right: \(right)")
        DispatchQueue.main.async {
            self.leftLevel = left
            self.rightLevel = right
            self.isSilent = left < self.silenceThreshold && right < self.silenceThreshold
            self.isOvermodulated = left > self.overmodulationThreshold || right > self.overmodulationThreshold
        }
    }
    
    func calculateLevel(from channel: UnsafePointer<Float>, count: Int) -> Float {
        var sum: Float = 0.0
        vDSP_measqv(channel, 1, &sum, vDSP_Length(count))
        let rms = sqrt(sum)
        let db = 20 * log10(rms)
        return max(db, -80.0)
    }
}

