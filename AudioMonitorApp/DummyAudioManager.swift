import Foundation
import Combine
import AVFoundation
import CoreAudio

@MainActor
final class DummyAudioManager: AudioManagerProtocol {
    private let statsSubject = CurrentValueSubject<AudioStats, Never>(.zero)
    private let inputDevicesSubject = CurrentValueSubject<[InputAudioDevice], Never>([
        InputAudioDevice(id: AudioObjectID(999), name: "Dummy Device", channelCount: 2)
    ])
    private let selectedDeviceSubject = CurrentValueSubject<InputAudioDevice, Never>(
        InputAudioDevice(id: AudioObjectID(999), name: "Dummy Device", channelCount: 2)
    )
    
    var leftLevel: Float { statsSubject.value.left }
    var rightLevel: Float { statsSubject.value.right }
    
    var audioStatsStream: AnyPublisher<AudioStats, Never> { statsSubject.eraseToAnyPublisher() }
    var inputDevicesStream: AnyPublisher<[InputAudioDevice], Never> { inputDevicesSubject.eraseToAnyPublisher() }
    var selectedInputDeviceStream: AnyPublisher<InputAudioDevice, Never> { selectedDeviceSubject.eraseToAnyPublisher() }
    
    var isRunning: Bool { false }
    
    init() {}
    
    func updateLogManager(_ logManager: any LogManagerProtocol) {
            // no-op
    }
    
    func selectDevice(_ device: InputAudioDevice) {
        selectedDeviceSubject.send(device)
    }
    
    func start() {
            // no-op
    }
    
    func stop() {
            // no-op
    }
    
    func simulateAudioLevels(left: Float, right: Float) {
            // Use the minimal initializer your AudioStats supports; if yours has defaults for the extras, this works as-is.
        let sel = selectedDeviceSubject.value
        let stats = AudioStats(
            left: left,
            right: right,
            inputName: sel.name,
            inputID: Int(sel.id)
        )
        statsSubject.send(stats)
    }
}

