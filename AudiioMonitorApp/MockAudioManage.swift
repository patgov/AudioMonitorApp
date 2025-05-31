import Foundation
import Combine
import AVFoundation

@MainActor
public final class MockAudioManager: AudioManagerProtocol {
    private let statsSubject = CurrentValueSubject<AudioStats, Never>(.preview)
    private let inputDevicesSubject = CurrentValueSubject<[InputAudioDevice], Never>([
        InputAudioDevice(id: "mock-1", uid: "mock-1", name: "Mock Mic 1", audioObjectID: AudioObjectID(999), channelCount: 2),
        InputAudioDevice(id: "mock-2", uid: "mock-2", name: "Mock Mic 2", audioObjectID: AudioObjectID(999),channelCount: 2)
    ])
    private let selectedDeviceSubject = CurrentValueSubject<InputAudioDevice, Never>(
        InputAudioDevice(id: "mock-1", uid: "mock-1", name: "Mock Mic 1", audioObjectID: AudioObjectID(999),channelCount: 2)
    )
        // MARK: - Required Protocol Properties
    
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
    
        // MARK: - Initialization
    
    public init() {
            // Send preview stats on init
        statsSubject.send(.preview)
    }
    
    public var isRunning: Bool {
        false
    }
    
        // MARK: - Protocol Method Stubs
    
    public func updateLogManager(_ logManager: any LogManagerProtocol) {
            // No-op for mock
    }
    
    public func selectDevice(_ device: InputAudioDevice) {
        selectedDeviceSubject.send(device)
    }
    
    public func start() {
            // Simulate streaming update
        statsSubject.send(AudioStats.preview)
    }
    
    public func stop() {
            // No-op
    }
}


