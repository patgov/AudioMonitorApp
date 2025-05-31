import Foundation
import AVFoundation

enum AudioDiagnostics {
    
    static let silenceThreshold: Float = -50.0
    static let overmodulationThreshold: Float = -2.0
    
    static func silenceThresholdLabel() -> String { "Silence threshold = \(silenceThreshold) dB" }
    static func overmodulationThresholdLabel() -> String { "Overmodulation threshold = \(overmodulationThreshold) dB" }
    
    @MainActor static func warnIfMonoDeviceSelected(_ device: InputAudioDevice?, logger: LogManager?) {
        guard let device = device, device != .none else { return }
        if device.channelCount < 2 {
            logger?.addWarning(message: "Mono input device selected: \(device.name)", channel: -1, value: Float(device.channelCount))
            print("⚠️ Warning: Mono input device selected: \(device.name)")
        }
    }
    
    @MainActor static func analyzeSilence(level: Float, threshold: Float, channels: Int, device: InputAudioDevice?, logger: LogManager?) {
        warnIfMonoDeviceSelected(device, logger: logger)
        if level.isNaN {
            print("⚠️ Invalid silence level (NaN) detected")
            return
        }
        if channels < 2 {
            logger?.addWarning(message: "Mono input detected during silence analysis", channel: -1, value: level)
            print("⚠️ Warning: Mono input detected during silence analysis")
        }
        if level < threshold {
            logger?.addWarning(message: "Silence detected (analysis)", channel: -1, value: level)
            print("🔍 Silence detected: level = \(level)")
        }
    }
    
    @MainActor static func analyzeOvermodulation(level: Float, threshold: Float, channels: Int, device: InputAudioDevice?, logger: LogManager?) {
        warnIfMonoDeviceSelected(device, logger: logger)
        if level.isNaN {
            print("⚠️ Invalid overmodulation level (NaN) detected")
            return
        }
        if channels < 2 {
            logger?.addWarning(message: "Mono input detected during overmodulation analysis", channel: -1, value: level)
            print("⚠️ Warning: Mono input detected during overmodulation analysis")
        }
        if level > threshold {
            logger?.addError(message: "Overmodulation detected (analysis)", channel: -1, value: level)
            print("🚨 Overmodulation detected: level = \(level)")
        }
    }
}





enum AudioDiagnosticsTools{
    
    static func calculateRMS(from channel: UnsafePointer<Float>, frameLength: Int) -> Float {
        let sumSquares = (0..<frameLength).map { channel[$0] * channel[$0] }.reduce(0, +)
        let rms = sqrt(sumSquares / Float(frameLength))
        return max(-80.0, 20 * log10(rms))
    }
    
    static func calculatePeak(from channel: UnsafePointer<Float>, frameLength: Int) -> Float {
        return (0..<frameLength).map { abs(channel[$0]) }.max() ?? 0.0
    }
    
    static func analyzeSilence(level: Float, threshold: Float) -> Bool {
        return level < threshold
    }
}


enum DiagnosticLevel: String, Codable {
    case info
    case warning
    case error
}

struct AudioDiagnosticsEngine: Identifiable, Codable {
    var id = UUID()
    let timestamp: Date
    let message: String
    let channel: Int
    let value: Float
    let level: DiagnosticLevel
    
    init(timestamp: Date = Date(), message: String, channel: Int, value: Float, level: DiagnosticLevel) {
        self.timestamp = timestamp
        self.message = message
        self.channel = channel
        self.value = value
        self.level = level
    }
}
