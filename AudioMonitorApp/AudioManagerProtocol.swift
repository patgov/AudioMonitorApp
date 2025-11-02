import Foundation
import AVFoundation
import Combine

@MainActor
 protocol AudioManagerProtocol: AnyObject {
        /// Current left channel audio level in dB.
    var leftLevel: Float { get }

        /// Current right channel audio level in dB.
    var rightLevel: Float { get }

        /// Stream of full audio stats (left, right, metadata).
    var audioStatsStream: AnyPublisher<AudioStats, Never> { get }

        /// Stream of available input devices.
    var inputDevicesStream: AnyPublisher<[InputAudioDevice], Never> { get }

        /// Stream of selected input device.
    var selectedInputDeviceStream: AnyPublisher<InputAudioDevice, Never> { get }
    
    var isRunning: Bool { get }

        /// Updates the log manager (used for tagging logs with device info).
    func updateLogManager(_ logManager: any LogManagerProtocol)

        /// Selects a new input device for monitoring.
    func selectDevice(_ device: InputAudioDevice)

        /// Starts audio monitoring.
    func start()

        /// Stops audio monitoring.
    func stop()
} // Final
