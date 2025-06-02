import CoreAudio
import AudioToolbox
import Foundation

final class CoreAudioInputDeviceManager {
        /// Returns the names of all input-capable audio devices on the system,
        /// including hardware microphones and virtual devices (e.g., BlackHole, Parallels Sound).
        ///
        /// This method uses CoreAudio HAL APIs to enumerate `AudioDeviceID`s and filter
        /// those with input streams. Device names are retrieved using `kAudioObjectPropertyName`,
        /// and wrapped using `Unmanaged<CFString>` to safely interface with CoreFoundation.
        ///
        /// - Returns: An array of input-capable audio device names as `[String]`.
    static func getAllInputDeviceNames() -> [String] {
        var deviceCount: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size * 32)
        var deviceIDs = [AudioDeviceID](repeating: 0, count: 32)
        var availableInputDevices: [String] {
            CoreAudioInputDeviceManager.getAllInputDeviceNames()
        }
        var devicesPropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesPropertyAddress,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )

        guard status == noErr else {
            print("Failed to get device list: \(status)")
            return []
        }

        deviceCount = propertySize / UInt32(MemoryLayout<AudioDeviceID>.size)

        var inputDeviceNames: [String] = []

        for i in 0..<Int(deviceCount) {
            let deviceID = deviceIDs[i]

            var inputStreams: UInt32 = 0
            var streamPropertySize = UInt32(MemoryLayout<UInt32>.size)
            var inputScope = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            let hasInput = AudioObjectGetPropertyData(
                deviceID,
                &inputScope,
                0,
                nil,
                &streamPropertySize,
                &inputStreams
            ) == noErr && streamPropertySize > 0

            if hasInput {
                    // CoreAudio does not transfer ownership here, so unretained is correct
                var name: Unmanaged<CFString>? = nil
                var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

                var nameAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioObjectPropertyName,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )

                if AudioObjectGetPropertyData(
                    deviceID,
                    &nameAddress,
                    0,
                    nil,
                    &nameSize,
                    &name
                ) == noErr, let unmanagedName = name {
                    inputDeviceNames.append(unmanagedName.takeUnretainedValue() as String)
                }
            }
        }

        return inputDeviceNames
    }

    static func getAllInputDevices() -> [(id: AudioDeviceID, name: String)] {
        var deviceCount: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size * 32)
        var deviceIDs = [AudioDeviceID](repeating: 0, count: 32)
        var devicesPropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesPropertyAddress,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )

        guard status == noErr else {
            print("Failed to get device list: \(status)")
            return []
        }

        deviceCount = propertySize / UInt32(MemoryLayout<AudioDeviceID>.size)

        var inputDevices: [(id: AudioDeviceID, name: String)] = []

        for i in 0..<Int(deviceCount) {
            let deviceID = deviceIDs[i]

            var inputStreams: UInt32 = 0
            var streamPropertySize = UInt32(MemoryLayout<UInt32>.size)
            var inputScope = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            let hasInput = AudioObjectGetPropertyData(
                deviceID,
                &inputScope,
                0,
                nil,
                &streamPropertySize,
                &inputStreams
            ) == noErr && streamPropertySize > 0

            if hasInput {
                var name: Unmanaged<CFString>? = nil
                var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
                var nameAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioObjectPropertyName,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )

                if AudioObjectGetPropertyData(
                    deviceID,
                    &nameAddress,
                    0,
                    nil,
                    &nameSize,
                    &name
                ) == noErr, let unmanagedName = name {
                    inputDevices.append((id: deviceID, name: unmanagedName.takeUnretainedValue() as String))
                }
            }
        }

        return inputDevices
    }
}
    /// Registers a listener to be called when the system's audio device list changes (e.g., devices added/removed).
    /// The `onChange` closure is called on the main thread when device changes are detected.
func registerDeviceChangeListener(_ onChange: @escaping () -> Void) {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    let listenerBlock: AudioObjectPropertyListenerBlock = { _, _ in
        onChange()
    }

    let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
    AudioObjectAddPropertyListenerBlock(systemObjectID, &address, DispatchQueue.main, listenerBlock)
}
