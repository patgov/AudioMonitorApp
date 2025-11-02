import AVFoundation
import Combine

@MainActor
class InputAudioMonitor: ObservableObject {
    public static let shared = InputAudioMonitor()
    
    private let engine = AVAudioEngine()
    private var inputNode: AVAudioInputNode?
    private let bufferSize: AVAudioFrameCount = 1024
    
    @Published public var currentLevelDB: Float = -160.0
    
    private init() {}
    
    public func startMonitoring() {
        inputNode = engine.inputNode
        let format = inputNode!.inputFormat(forBus: 0)
        
        inputNode!.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }

            var sumSquares: Float = 0
            for i in 0..<frameLength {
                let s = channelData[i]
                sumSquares += s * s
            }
            let meanSquare = sumSquares / Float(frameLength)
            let rms = sqrtf(meanSquare)
            let avgPower = rms > 0 ? 20 * log10f(rms) : -160.0

            Task { @MainActor in
                self.currentLevelDB = avgPower.isFinite ? avgPower : -160.0
            }
        }
        
        do {
            try engine.start()
        } catch {
            print("⚠️ Could not start AVAudioEngine: \(error)")
        }
    }
    
    public func stopMonitoring() {
        inputNode?.removeTap(onBus: 0)
        engine.stop()
    }
}
    /// add visualize level in the UI.

