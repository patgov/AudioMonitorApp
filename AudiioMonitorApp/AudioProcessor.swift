/*
 AudioProcessor is responsible for analyzing real-time audio levels and routing the results via audioStatsStream. If it’s broken or misaligned with the new protocols (especially AudioStats), everything downstream (VU meters, log viewer, diagnostics) will also bre

 2.    Isolated and Testable
 It’s largely self-contained — it takes audio input, processes it, and emits AudioStats. This makes it easier to unit test and debug without needing the full UI stack.
 3.    Directly Tied to Protocol Compatibility
 Fixing it early lets you validate:
 •    AudioStats.init(...) is used with the new parameters (left, right, inputName, inputID)
 •    That Combine publishers (audioStatsStream) conform to expectations in AudioManagerProtocol
 4.    Unblocks Preview and UI Fixes
 Once AudioProcessor outputs valid stats, you can immediately see progress in views like AudioMonitorView, AudioStatsView, and VU meters.

 ⚠️ What to watch for when patching:
 •    AudioStats now requires inputName and inputID — make sure AudioProcessor is updated to pass these along.
 •    Ensure @Published or PassthroughSubject<AudioStats, Never> is correctly used if using Combine.
 •    Validate that AudioProcessor is called from the correct dispatch queue (typically real-time or a background queue).
 •    Confirm your AudioManager is injecting the right input device info into AudioProcessor.
 */



import AVFoundation
import OSLog
import Combine

public final class AudioProcessor {
    public private(set) var currentLeftLevel: Float = -80.0
    public private(set) var currentRightLevel: Float = -80.0

    public let audioStatsStream = PassthroughSubject<AudioStats, Never>()
    public init() {}

    public func process(buffer: AVAudioPCMBuffer) -> (left: Float, right: Float) {
        guard let channelData = buffer.floatChannelData else {
            return (-80.0, -80.0)
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        let leftRMS = calculateRMS(samples: channelData[0], count: frameLength)
        let rightRMS = channelCount > 1
        ? calculateRMS(samples: channelData[1], count: frameLength)
        : leftRMS

        let leftDB = max(-80, min(6, 20 * log10(leftRMS + .leastNonzeroMagnitude)))
        let rightDB = max(-80, min(6, 20 * log10(rightRMS + .leastNonzeroMagnitude)))

        return (leftDB, rightDB)
    }

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

        let leftDB = max(-80, min(6, 20 * log10(leftRMS + .leastNonzeroMagnitude)))
        let rightDB = max(-80, min(6, 20 * log10(rightRMS + .leastNonzeroMagnitude)))

        currentLeftLevel = max(-80, min(6, leftDB))
        currentRightLevel = max(-80, min(6, rightDB))

        print("🎚️ AudioProcessor - dB levels → Left: \(currentLeftLevel), Right: \(currentRightLevel), Device: \(inputName) [\(inputID)]")
        let stats = AudioStats(left: currentLeftLevel, right: currentRightLevel, inputName: inputName, inputID: inputID)
        audioStatsStream.send(stats)
        print("📤 AudioStats emitted: \(stats)")
    }

    private func calculateRMS(samples: UnsafePointer<Float>, count: Int) -> Float {
        var sum: Float = 0.0
        for i in 0..<count {
            let value = samples[i]
            sum += value * value
        }
        return sqrt(sum / Float(count))
    }

    public func format(_ value: Float, precision: Int = 1) -> String {
        let clampedValue = value.isFinite ? max(min(value, 6.0), -80.0) : -80.0
        return String(format: "%.\(precision)f", clampedValue)
    }
}

    // Logger+Categories.swift

