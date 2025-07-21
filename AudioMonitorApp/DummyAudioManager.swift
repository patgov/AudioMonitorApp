import Foundation
import Combine
import AVFoundation
import CoreAudio

@MainActor
public final class DummyAudioManager: AudioManagerProtocol {
    private let statsSubject = CurrentValueSubject<AudioStats, Never>(.zero)
    private let inputDevicesSubject = CurrentValueSubject<[InputAudioDevice], Never>([
        InputAudioDevice(id: "dummy", uid: "dummy-uid", name: "Dummy Device", audioObjectID: AudioObjectID(999), channelCount: 2)
    ])
    private let selectedDeviceSubject = CurrentValueSubject<InputAudioDevice, Never>(
        InputAudioDevice(id: "dummy", uid: "dummy-uid", name: "Dummy Device", audioObjectID: AudioObjectID(999), channelCount: 2)
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
            // no-op
    }
    
    public func selectDevice(_ device: InputAudioDevice) {
        selectedDeviceSubject.send(device)
    }
    
    public func start() {
            // no-op
    }
    
    public func stop() {
            // no-op
    }
    
}
