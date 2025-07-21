import Foundation
import AVFoundation
import Combine

public final class AudioProcessor {
    public private(set) var currentLeftLevel: Float = -80.0
    public private(set) var currentRightLevel: Float = -80.0
    
    public let audioStatsStream = PassthroughSubject<AudioStats, Never>()
    
        /// Initializes a new `AudioProcessor` for computing real-time audio levels.
        /// The processor uses a Combine publisher to emit `AudioStats` for display and logging.
    public init() {}
    
        /// Processes the audio buffer and returns raw dBFS levels for left and right channels.
        ///
        /// - Parameter buffer: The audio buffer to analyze.
        /// - Returns: A tuple containing the calculated left and right channel dB levels.
    public func process(buffer: AVAudioPCMBuffer) -> (left: Float, right: Float) {
            // Please use process(buffer:inputName:inputID:) with labeled arguments instead.
        fatalError("Use process(buffer:inputName:inputID:) with labeled arguments.")
    }
    
        /// Processes the audio buffer, computes stereo dB levels, and emits `AudioStats` via Combine.
        ///
        /// - Parameters:
        ///   - buffer: The input audio buffer.
        ///   - inputName: The name of the selected audio input device.
        ///   - inputID: The ID of the selected audio input device.
        /// - Note: This method updates the current left and right dB levels and sends an `AudioStats` event.
    public func process(buffer: AVAudioPCMBuffer, inputName: String, inputID: Int) {
        guard let channelData = buffer.floatChannelData else {
            return
        }
        
            // Log a raw sample for debug
        let sample = channelData[0].pointee
        print("🔊 First sample (L):", sample)
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        let leftRMS = calculateRMS(samples: channelData[0], count: frameLength)
        let rightRMS: Float
        if channelCount > 1 {
            rightRMS = calculateRMS(samples: channelData[1], count: frameLength)
        } else {
            rightRMS = leftRMS // Mirror mono signal to right
            print("⚠️ Mono input detected — mirroring to both channels")
        }
        
        let leftDB = 20 * log10(leftRMS + .leastNonzeroMagnitude)
        let rightDB = 20 * log10(rightRMS + .leastNonzeroMagnitude)
        
            // Do not clamp these dB values here; emit raw dB values for downstream consumers.
        currentLeftLevel = leftDB
        currentRightLevel = rightDB
        
        print("🎚️ AudioProcessor - dB levels → Left: \(currentLeftLevel), Right: \(currentRightLevel), Device: \(inputName) [\(inputID)]")
        if currentLeftLevel == -80.0 && currentRightLevel == -80.0 {
            print("❌ AudioProcessor warning: Both channels are at floor level. Audio input may be disconnected or silent.")
        }
            // Emit raw dB values directly — do not clamp to -80 dBFS here.
            // Visualization (e.g., VU meters) will apply display clamping and mapping.
        let stats = AudioStats(left: currentLeftLevel, right: currentRightLevel, inputName: inputName, inputID: inputID)
        audioStatsStream.send(stats)
        print("📤 AudioStats emitted: \(stats)")
    }
    
        /// Calculates the root mean square (RMS) of a buffer of Float audio samples.
        ///
        /// - Parameters:
        ///   - samples: Pointer to the array of audio sample values.
        ///   - count: Number of samples in the buffer.
        /// - Returns: The RMS value, clamped to a minimum threshold to avoid log10 underflow.
    private func calculateRMS(samples: UnsafePointer<Float>, count: Int) -> Float {
        var sum: Float = 0.0
        for i in 0..<count {
            let value = samples[i]
            sum += value * value
        }
        let rms = sqrt(sum / Float(count))
        return max(rms, 0.000_001) // Clamp to prevent log10 from returning large negative dB
    }
    
        /// Formats a float value as a string with the given precision, clamping non-finite values.
        ///
        /// - Parameters:
        ///   - value: The float value to format.
        ///   - precision: Number of decimal places to include.
        /// - Returns: A formatted string representation of the float value.
    public func format(_ value: Float, precision: Int = 1) -> String {
        let clampedValue = value.isFinite ? value : -80.0
        return String(format: "%.\(precision)f", clampedValue)
    }
}
