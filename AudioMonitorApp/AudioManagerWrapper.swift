import Foundation
import Combine
import SwiftUI

final class AudioManagerWrapper: ObservableObject, AudioManagerProtocol {
    
    @Published public private(set) var audioStats: AudioStats = .zero
    @Published public private(set) var inputDevices: [InputAudioDevice] = []
    @Published public private(set) var selectedInputDevice: InputAudioDevice = .none
    
    private var cancellables = Set<AnyCancellable>()
    private let manager: any AudioManagerProtocol
    
    public init(manager: any AudioManagerProtocol) {
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
    
        // MARK: - AudioManagerProtocol
    
    public var leftLevel: Float { audioStats.left }
    public var rightLevel: Float { audioStats.right }
    public var inputName: String { audioStats.inputName }
    public var inputID: Int { audioStats.inputID }
    
    public var audioStatsStream: AnyPublisher<AudioStats, Never> {
        $audioStats.eraseToAnyPublisher()
    }
    
    public var inputDevicesStream: AnyPublisher<[InputAudioDevice], Never> {
        $inputDevices.eraseToAnyPublisher()
    }
    
    public var selectedInputDeviceStream: AnyPublisher<InputAudioDevice, Never> {
        $selectedInputDevice.eraseToAnyPublisher()
    }
    
    public var isRunning: Bool {
        (manager as? AudioManager)?.isRunning ?? false
    }
    
    public func selectDevice(_ device: InputAudioDevice) {
        manager.selectDevice(device)
    }
    
    public func updateLogManager(_ logManager: any LogManagerProtocol) {
        manager.updateLogManager(logManager)
    }
    
    public func start() {
        manager.start()
    }
    
    public func stop() {
        manager.stop()
    }
}

