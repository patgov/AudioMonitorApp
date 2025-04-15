import AVFoundation

class AudioManager: ObservableObject {
    private let engine = AVAudioEngine()
    private var inputNode: AVAudioInputNode?
    private(set) var processor: AudioProcessor
    var logManager: LogManager?

    @Published var leftLevel: Float = -80.0
    @Published var rightLevel: Float = -80.0
    var currentInputName: String = "Unknown"
    var currentInputID: Int  = -1

    init(processor: AudioProcessor, logManager: LogManager? = nil) {
        self.processor = processor
        self.logManager = logManager
    }

    func updateLogManager(_ logManager: LogManager) {
        self.logManager = logManager
    }

    func start() {
        autoSelectBestInputDevice()

       

        installTap()

            // Ensure the input node is connected (important on macOS)
        engine.prepare()

        do {
            try engine.start()
            print("🎧 Audio engine started.")
        } catch {
            print("❌ Failed to start audio engine: \(error)")
        }
    }

    func stop() {
        engine.stop()
        inputNode?.removeTap(onBus: 0)
        print("🛑 Audio engine stopped.")
    }

    private func installTap() {
        inputNode = engine.inputNode
        inputNode?.removeTap(onBus: 0)

        let format = inputNode?.inputFormat(forBus: 0)
        ?? AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        print("🎚 Input format: \(format)")
        print("🎚 Channel count: \(format.channelCount)")

        inputNode?.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            print("🔊 Sample left[0]: \(channelData[0][0])")
            if format.channelCount > 1 {
                print("🔊 Sample right[0]: \(channelData[1][0])")
            }
            let left = self.processor.calculateLevel(from: channelData[0], count: frameCount)
            let right = buffer.format.channelCount > 1
            ? self.processor.calculateLevel(from: channelData[1], count: frameCount)
            : left

            DispatchQueue.main.async {
                self.leftLevel = left
                self.rightLevel = right
                self.processor.leftLevel = left
                self.processor.rightLevel = right
                self.processor.process(buffer: buffer)

                if let logManager = self.logManager {
                    logManager.processLevel(left, channel: 0, inputName: self.currentInputName, inputID: Int(self.currentInputID))
                    logManager.processLevel(right, channel: 1, inputName: self.currentInputName, inputID: Int(self.currentInputID))
                }

                print("🎚 Left level: \(left), Right level: \(right)")
            }
        }

        print("📡 Tap installed on input node.")
    }

    private func autoSelectBestInputDevice() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )

        guard status == noErr else { return }

        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceIDs
        )

        guard status == noErr else { return }

        for deviceID in deviceIDs {
            if let name = getDeviceName(for: deviceID)?.lowercased() {
                print("🎙 Device found: \(name)")
                if name.contains("camera") || name.contains("virtual") || name.contains("parallels") {
                    continue
                }
                if name.contains("mic") || name.contains("built-in") || name.contains("usb") {
                    print("🎤 Auto-selected input: \(name)")
                    currentInputName = name
                    currentInputID = Int(deviceID)
                    setInputDevice(deviceID)
                    return
                }
            }
        }
    }

    private func getDeviceName(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var namePtr: Unmanaged<CFString>?

        let status = withUnsafeMutablePointer(to: &namePtr) { ptr -> OSStatus in
            return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
        }

        if status == noErr, let nameCF = namePtr?.takeRetainedValue() {
            return nameCF as String
        }
        return nil
    }

    private func setInputDevice(_ deviceID: AudioDeviceID) {
        var deviceID = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )

        if status != noErr {
            print("❌ Failed to set input device. Status: \(status)")
        }
    }
}
