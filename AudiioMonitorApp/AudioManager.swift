import OSLog
import Combine
import AVFoundation


public final class AudioManager: ObservableObject, AudioManagerProtocol {

    private let logger = Logger.audioManager

    private var selectedInputDeviceSubject = CurrentValueSubject<InputAudioDevice, Never>(.none)
    private var inputDevicesSubject = CurrentValueSubject<[InputAudioDevice], Never>([])
    private var selectedDevice: InputAudioDevice = .none
    private var logManager: LogManagerProtocol?
        // Placeholder for stats subject, to be replaced with real implementation later
    private var statsSubject = CurrentValueSubject<AudioStats, Never>(.zero)

    private var audioEngine: AVAudioEngine?
    private let audioProcessor = AudioProcessor()
    private var cancellables = Set<AnyCancellable>()

    public var leftLevel: Float {
        return audioProcessor.currentLeftLevel
    }

    public var rightLevel: Float {
        return audioProcessor.currentRightLevel
    }

    public var isRunning: Bool {
        return audioEngine?.isRunning ?? false
    }

    public var audioStatsStream: AnyPublisher<AudioStats, Never> {
        statsSubject.eraseToAnyPublisher()
    }

    public var inputDevicesStream: AnyPublisher<[InputAudioDevice], Never> {
        inputDevicesSubject.eraseToAnyPublisher()
    }

    public var selectedInputDeviceStream: AnyPublisher<InputAudioDevice, Never> {
        selectedInputDeviceSubject.eraseToAnyPublisher()
    }

    public func updateLogManager(_ logManager: any LogManagerProtocol) {
            // Implementation pending – ensure there's a stored reference if needed
        self.logManager = logManager
    }

    public func selectDevice(_ device: InputAudioDevice) {
        selectedDevice = device
        selectedInputDeviceSubject.send(device)
    }

    public func start() {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            logger.warning("🛑 [Preview Diagnostic] AudioManager.start() was triggered during SwiftUI Preview!")
        } else {
            logger.info("✅ [Runtime] AudioManager.start() running in normal app mode.")
        }
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else {
            logger.info("⏸️ Skipping audio engine start in SwiftUI preview mode.")
            return
        }
        let engine = AVAudioEngine()
        self.audioEngine = engine

        audioProcessor.audioStatsStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stats in
                self?.statsSubject.send(stats)
            }
            .store(in: &cancellables)

        let inputNode = engine.inputNode
        let hwFormat = inputNode.inputFormat(forBus: 0)
        logger.info("🔍 InputNode HW format: \(hwFormat.sampleRate) Hz, \(hwFormat.channelCount) ch")

            // Use hardware format directly for tap, remove any custom AVAudioFormat usage.
        if inputNode.numberOfInputs > 0 {
            inputNode.removeTap(onBus: 0)
        }

        logger.info("🔍 Installing tap with confirmed HW format: \(hwFormat)")

        inputNode.installTap(onBus: 0, bufferSize: 4800, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            self.audioProcessor.process(buffer: buffer,
                                        inputName: self.selectedDevice.name,
                                        inputID: self.selectedDevice.id.hashValue)
        }

        do {
            try engine.start()
            logger.info("🎧 Audio engine started.")
        } catch {
            logger.error("❌ Engine failed to start after tap install: \(error.localizedDescription)")
            return
        }

        refreshAvailableDevices()
    }

    public func stop() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        logger.info("🛑 Audio engine stopped.")
    }




    private func refreshAvailableDevices() {
#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        let devices = session.availableInputs?.map {
            InputAudioDevice(id: $0.uid, name: $0.portName, isBlackHole: false)
        } ?? []
        inputDevicesSubject.send(devices)
#else
            // macOS (not Catalyst): fetch live devices using Core Audio utilities.
        let allDevices = InputAudioDevice.fetchAvailableDevices()
        print("🛠️ All discovered devices: \(allDevices.map(\.displayName))")

            // Determine system default input
        let defaultDeviceID = InputAudioDevice.fetchDefaultInputDeviceID()
        let fallbackDevice = allDevices.first(where: { $0.audioObjectID == defaultDeviceID }) ?? .none

        if allDevices.isEmpty {
            logger.warning("⚠️ No input devices found. Prompt user to select one from System Settings > Sound > Input.")
            DispatchQueue.main.async {
                let fallbackStats = AudioStats.zero
                self.statsSubject.send(fallbackStats)
            }
        } else if fallbackDevice == .none {
            logger.warning("⚠️ No input device is selected. Choose a device if needed.")
        } else {
            logger.info("🎧 System input device: \(fallbackDevice.name) [\(fallbackDevice.id)]")
        }

            // Publish full list with fallback
        inputDevicesSubject.send([.none] + allDevices)

            // Only override selection if none is set, or current device is not present
        if selectedDevice == .none || !allDevices.contains(selectedDevice) {
            if let blackHoleDevice = allDevices.first(where: { $0.name.contains("BlackHole 2ch") }) {
                selectedDevice = blackHoleDevice
                selectedInputDeviceSubject.send(blackHoleDevice)
                logger.info("🎯 Auto-selected BlackHole 2ch device: \(blackHoleDevice.name) [\(blackHoleDevice.id)]")
            } else {
                selectedDevice = fallbackDevice
                selectedInputDeviceSubject.send(fallbackDevice)
                logger.warning("⚠️ Fallback selected: \(fallbackDevice.name) [\(fallbackDevice.id)]")
            }
        }
        logger.info("📦 Published \(allDevices.count) input devices to the UI.")
#endif
    }
}
