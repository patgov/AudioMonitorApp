import Foundation
import Combine
import AVFoundation

@MainActor
final class MockAudioManager: AudioManagerProtocol {
    private let statsSubject = CurrentValueSubject<AudioStats, Never>(.preview)
    private let inputDevicesSubject = CurrentValueSubject<[InputAudioDevice], Never>([
        InputAudioDevice(id: 999, name: "Mock Mic 1", channelCount: 2),
        InputAudioDevice(id: 1000, name: "Mock Mic 2", channelCount: 2)
    ])
    private let selectedDeviceSubject = CurrentValueSubject<InputAudioDevice, Never>(
        InputAudioDevice(id: 999, name: "Mock Mic 1", channelCount: 2)
    )
    
        // MARK: - Protocol properties
    var leftLevel: Float { statsSubject.value.left }
    var rightLevel: Float { statsSubject.value.right }
    
    var audioStatsStream: AnyPublisher<AudioStats, Never> { statsSubject.eraseToAnyPublisher() }
    var inputDevicesStream: AnyPublisher<[InputAudioDevice], Never> { inputDevicesSubject.eraseToAnyPublisher() }
    var selectedInputDeviceStream: AnyPublisher<InputAudioDevice, Never> { selectedDeviceSubject.eraseToAnyPublisher() }
    
        // MARK: - Init
    init() {
        statsSubject.send(.preview)
    }
    
    var isRunning: Bool { false }
    
        // MARK: - Protocol methods
    func updateLogManager(_ logManager: any LogManagerProtocol) {
            // No-op in mock
    }
    
    func selectDevice(_ device: InputAudioDevice) {
        selectedDeviceSubject.send(device)
    }
    
    func start() {
            // Simulate streaming update
        statsSubject.send(.preview)
    }
    
    func stop() {
            // No-op
    }
}

