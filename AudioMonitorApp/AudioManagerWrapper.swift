import Foundation
import Combine
import SwiftUI

@MainActor
final class AudioManagerWrapper: ObservableObject, AudioManagerProtocol {
    
    @Published private(set) var audioStats: AudioStats = .zero
    @Published private(set) var inputDevices: [InputAudioDevice] = []
    @Published private(set) var selectedInputDevice: InputAudioDevice = .none
    
    private var cancellables = Set<AnyCancellable>()
    private let manager: any AudioManagerProtocol
    
    init(manager: any AudioManagerProtocol) {
        self.manager = manager
        
        manager.audioStatsStream
            .receive(on: DispatchQueue.main)
            .assign(to: &$audioStats)
        
        manager.inputDevicesStream
            .receive(on: DispatchQueue.main)
            .assign(to: &$inputDevices)
        
        manager.selectedInputDeviceStream
            .receive(on: DispatchQueue.main)
            .assign(to: &$selectedInputDevice)
    }
    
        // AudioManagerProtocol passthrough
    var leftLevel: Float { audioStats.left }
    var rightLevel: Float { audioStats.right }
    var audioStatsStream: AnyPublisher<AudioStats, Never> { $audioStats.eraseToAnyPublisher() }
    var inputDevicesStream: AnyPublisher<[InputAudioDevice], Never> { $inputDevices.eraseToAnyPublisher() }
    var selectedInputDeviceStream: AnyPublisher<InputAudioDevice, Never> { $selectedInputDevice.eraseToAnyPublisher() }
    var isRunning: Bool { manager.isRunning }
    
    func selectDevice(_ device: InputAudioDevice) { manager.selectDevice(device) }
    func updateLogManager(_ logManager: any LogManagerProtocol) { manager.updateLogManager(logManager) }
    func start() { manager.start() }
    func stop() { manager.stop() }
}


