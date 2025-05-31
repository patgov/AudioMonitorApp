import Foundation
import Combine
import AVFoundation

@MainActor
public final class PlaceHolderAudioManager: AudioManagerProtocol {
    private let statsSubject = CurrentValueSubject<AudioStats, Never>(.zero)
    private let inputDevicesSubject = CurrentValueSubject<[InputAudioDevice], Never>([
        InputAudioDevice(id: "placeholder", uid: "placeholder", name: "Placeholder Input", audioObjectID: AudioObjectID(999), channelCount: 2)
    ])
    private let selectedDeviceSubject = CurrentValueSubject<InputAudioDevice, Never>(
        InputAudioDevice(id: "placeholder", uid: "placeholder", name: "Placeholder Input", audioObjectID: AudioObjectID(999), channelCount: 2)
    )

    public var leftLevel: Float {
        statsSubject.value.left
    }

    public var rightLevel: Float {
        statsSubject.value.right
    }

    public var audioStatsStream: AnyPublisher<AudioStats, Never> {
        statsSubject.eraseToAnyPublisher()
    }

    public var inputDevicesStream: AnyPublisher<[InputAudioDevice], Never> {
        inputDevicesSubject.eraseToAnyPublisher()
    }

    public var selectedInputDeviceStream: AnyPublisher<InputAudioDevice, Never> {
        selectedDeviceSubject.eraseToAnyPublisher()
    }

    public var isRunning: Bool {
        false
    }

    public init() {}

    public func updateLogManager(_ logManager: any LogManagerProtocol) {
            // No-op
    }

    public func selectDevice(_ device: InputAudioDevice) {
        selectedDeviceSubject.send(device)
    }

    public func start() {
            // No-op
    }

    public func stop() {
            // No-op
    }
}
