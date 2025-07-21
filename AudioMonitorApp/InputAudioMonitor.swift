import AVFoundation
import Combine

@MainActor
public class InputAudioMonitor: ObservableObject {
    public static let shared = InputAudioMonitor()
    
    private var engine = AVAudioEngine()
    private var inputNode: AVAudioInputNode?
    private let bufferSize: AVAudioFrameCount = 1024
    
    @Published public var currentLevelDB: Float = -160.0
    
    private init() {}
    
    public func startMonitoring() {
        inputNode = engine.inputNode
        let format = inputNode!.inputFormat(forBus: 0)
        
        inputNode!.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, _ in
            self.process(buffer: buffer)
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
    
    private func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        let frameLength = Int(buffer.frameLength)
        let bufferPointer = UnsafeBufferPointer(start: channelData, count: frameLength)
        let samples = bufferPointer.map { $0 }
        
        let sumSquares = samples.map { $0 * $0 }.reduce(0, +)
        let meanSquare = sumSquares / Float(frameLength)
        let rms = sqrt(meanSquare)
        let avgPower = 20 * log10(rms)
        
        DispatchQueue.main.async {
            self.currentLevelDB = avgPower.isFinite ? avgPower : -160.0
        }
    }
}

    /// add visualize level in the UI.
