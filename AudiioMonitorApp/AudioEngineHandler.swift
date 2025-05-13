//
//  AudioEngineHandler.swift.swift
//  AudiioMonitorApp
//
//  Created by Pat Govan on 5/12/25.
//

import AVFoundation
import Foundation

    /// Handles audio engine setup, input format configuration, and buffer tap installation.
class AudioEngineHandler {
    private let engine = AVAudioEngine()
    private var inputNode: AVAudioInputNode? {
        engine.inputNode
    }

    var inputFormat: AVAudioFormat? {
        inputNode?.inputFormat(forBus: 0)
    }

        /// Starts the AVAudioEngine and installs a tap to capture audio buffers.
        /// - Parameters:
        ///   - onBuffer: Callback providing audio buffer for processing.
        /// - Throws: Any error encountered when starting the audio engine.
    func startEngine(onBuffer: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void) throws {
        guard let inputNode = inputNode else {
            throw NSError(domain: "AudioEngineHandler", code: -1, userInfo: [NSLocalizedDescriptionKey: "No input node available"])
        }

        let format = inputNode.inputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
            onBuffer(buffer, time)
        }

        try engine.start()
    }

        /// Stops the AVAudioEngine and removes the input tap.
    func stopEngine() {
        inputNode?.removeTap(onBus: 0)
        engine.stop()
    }

        /// Returns the name of the current input device, if available.
    var currentInputDeviceName: String {
        AVAudioSession.sharedInstance().preferredInput?.portName ?? "Unknown"
    }
}

