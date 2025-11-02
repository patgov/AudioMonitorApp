import Foundation
import Combine
import AVFoundation

@MainActor
final class PlaceHolderAudioManager: AudioManagerProtocol {
    private let statsSubject = CurrentValueSubject<AudioStats, Never>(.zero)
    private let inputDevicesSubject = CurrentValueSubject<[InputAudioDevice], Never>([
        InputAudioDevice(id: 999, name: "Placeholder Input", channelCount: 2)
    ])
    private let selectedDeviceSubject = CurrentValueSubject<InputAudioDevice, Never>(
        InputAudioDevice(id: 999, name: "Placeholder Input", channelCount: 2)
    )
    
        // MARK: - Protocol properties
    var leftLevel: Float { statsSubject.value.left }
    var rightLevel: Float { statsSubject.value.right }
    
    var audioStatsStream: AnyPublisher<AudioStats, Never> { statsSubject.eraseToAnyPublisher() }
    var inputDevicesStream: AnyPublisher<[InputAudioDevice], Never> { inputDevicesSubject.eraseToAnyPublisher() }
    var selectedInputDeviceStream: AnyPublisher<InputAudioDevice, Never> { selectedDeviceSubject.eraseToAnyPublisher() }
    
    var isRunning: Bool { false }
    
    init() {}
    
        // MARK: - Protocol methods
    func updateLogManager(_ logManager: any LogManagerProtocol) {
            // No-op
    }
    
    func selectDevice(_ device: InputAudioDevice) {
        selectedDeviceSubject.send(device)
    }
    
    func start() {
            // No-op (or simulate a tick if you want)
        statsSubject.send(.zero)
    }
    
    func stop() {
            // No-op
    }
}

