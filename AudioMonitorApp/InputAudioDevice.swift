import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation

public struct InputAudioDevice: Identifiable, Hashable, Equatable, CustomStringConvertible, Comparable {
    public var isUserSelectable: Bool {
        return !name.contains("CADefaultDeviceAggregate") && isValid
    }

    public let id: String
    public let uid: String
    public let name: String
    public let audioObjectID: AudioObjectID
    public let isBlackHole: Bool

        /// Returns true if the device appears to be a virtual input device
    public var isVirtual: Bool {
        return name.lowercased().contains("loopback") || name.lowercased().contains("virtual")
    }

    public let channelCount: Int

    public init(id: String, uid: String, name: String, audioObjectID: AudioObjectID, channelCount: Int) {
        self.id = id
        self.uid = uid
        self.name = name
        self.audioObjectID = audioObjectID
        self.channelCount = channelCount
        self.isBlackHole = name.lowercased().contains("blackhole")
    }

        // Special "None" case
    public static let none = InputAudioDevice(id: "none", uid: "", name: "None", audioObjectID: 0, channelCount: 0)

        // MARK: - Visual Labeling

    public var displayName: String {
        if self == .none {
            return "🛑 None"
        } else if isActive {
            return "✅ \(name)"
        } else if isBlackHole {
            return "🕳️ \(name)"
        } else {
            return "🎧 \(name)"
        }
    }

    public var isValid: Bool {
        return channelCount > 0
    }

    public var hasChannels: Bool {
        return channelCount > 0
    }

    public var isSelectable: Bool {
        return self != .none && isValid
    }

    public var isActive: Bool {
        return self.audioObjectID == InputAudioDevice.fetchDefaultInputDeviceID()
    }

        /// A diagnostic label summarizing the device status visually for UI use.
        /// Combines the name with emoji for active, BlackHole, and invalid status.
        /// Use in SwiftUI pickers/lists instead of `name` or `displayName`.
    public var diagnosticLabel: String {
        var label = name
        if isActive {
            label += " ✅"
        }
        if isBlackHole {
            label += " 🕳️"
        }
        if !isValid {
            label += " ⚠️"
        }
        return label
    }

    public var description: String {
        "\(name) [\(id)]"
    }

        /// Returns true if the device is considered recently active.
        /// NOTE: Cannot access @MainActor InputAudioMonitor.shared from a nonisolated context.
        /// Use fallback logic here; real-time audio monitoring must be injected asynchronously.
    public var hasRecentActivity: Bool {
        return !isVirtual && isActive && isSelectable && channelCount > 0
    }

        // MARK: - Sorting

    public static func < (lhs: InputAudioDevice, rhs: InputAudioDevice) -> Bool {

        if lhs == .none { return true }
        if rhs == .none { return false }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    public static func == (lhs: InputAudioDevice, rhs: InputAudioDevice) -> Bool {
        return lhs.id == rhs.id
    }

    public var isSystemDefault: Bool {
        guard let defaultID = InputAudioDevice.fetchDefaultInputDeviceID() else {
            return false
        }
        return self.audioObjectID == defaultID
    }

    public static func fetchAvailableDevices() -> [InputAudioDevice] {
        var devices = [InputAudioDevice]()

        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize
        )
        if status != noErr {
            print("❌ Failed to get device data size: \(status)")
            return devices
        }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)

        let status2 = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )
        if status2 != noErr {
            print("❌ Failed to get device list: \(status2)")
            return devices
        }

        for id in deviceIDs {
            var nameCF: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<CFString?>.size)
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            let nameStatus = AudioObjectGetPropertyData(
                id,
                &nameAddress,
                0,
                nil,
                &nameSize,
                &nameCF
            )
            if nameStatus != noErr {
                print("❌ Failed to get name for device \(id): \(nameStatus)")
                continue
            }

            var uidCF: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<CFString?>.size)
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let uidStatus = AudioObjectGetPropertyData(
                id,
                &uidAddress,
                UInt32(0),
                nil,
                &uidSize,
                &uidCF
            )
            if uidStatus != noErr {
                print("❌ Failed to get UID for device \(id): \(uidStatus)")
                continue
            }
            guard let cfuid = uidCF?.takeRetainedValue() else {
                continue
            }
            let uid = cfuid as String

            let idString = String(id)

            var inputChannels: UInt32 = 0
            var inputSize = UInt32(0)
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )


            let inputStatus = AudioObjectGetPropertyDataSize(id, &inputAddress, 0, nil, &inputSize)
            if inputStatus != noErr {
                print("❌ Failed to get stream configuration size for device \(id): \(inputStatus)")
                continue
            }
            if inputStatus == noErr {
                let bufferListPtr = UnsafeMutableRawPointer.allocate(byteCount: Int(inputSize), alignment: MemoryLayout<AudioBufferList>.alignment)
                    .assumingMemoryBound(to: AudioBufferList.self)
                defer { bufferListPtr.deallocate() }
                var size = inputSize
                memset(bufferListPtr, 0, Int(size))
                let status = AudioObjectGetPropertyData(id, &inputAddress, 0, nil, &size, bufferListPtr)
                if status != noErr {
                    print("❌ Failed to get stream configuration data for device \(id): \(status)")
                    continue
                }
                if status == noErr {
                    let audioBufferList = UnsafeMutableAudioBufferListPointer(bufferListPtr)
                    for buffer in audioBufferList {
                        inputChannels += buffer.mNumberChannels
                    }
                }
            }

            if inputChannels == 0 {
                continue
            }

            var transportType: UInt32 = 0
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            var transportAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectGetPropertyData(id, &transportAddress, 0, nil, &transportSize, &transportType)

            let labeledName = nameCF!.takeRetainedValue() as String

            let device = InputAudioDevice(id: idString, uid: uid, name: labeledName, audioObjectID: id, channelCount: Int(inputChannels))
            if !device.isUserSelectable {
                continue
            }
            devices.append(device)
            print("🎙️ Discovered device: \(device.name), channels: \(inputChannels)")
        }

        return devices
    }

    public static func fetchDefaultInputDeviceID() -> AudioObjectID? {
        var defaultDeviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &defaultDeviceID
        )

        return status == noErr ? defaultDeviceID : nil
    }

    public static func fetchCurrentDefaultInputDeviceName() -> String {
        guard let defaultID = fetchDefaultInputDeviceID() else { return "Unknown Device" }

        var nameCF: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            defaultID,
            &nameAddress,
            0,
            nil,
            &nameSize,
            &nameCF
        )

        guard status == noErr, let cfName = nameCF?.takeRetainedValue() else {
            return "Unknown Device"
        }

        return cfName as String
    }

    public static func setSystemDefaultInputDevice(to id: AudioObjectID) -> Bool {
        var newDeviceID = id
        let propertySize = UInt32(MemoryLayout<AudioObjectID>.size)
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
            propertySize,
            &newDeviceID
        )

        return status == noErr
    }

        /// Returns true if the device is considered recently active.
        /// Returns true if the device is considered recently active.
        /// NOTE: Cannot access @MainActor property from sync context.
        /// Recommend injecting recentLevel from a ViewModel or diagnostics manager instead.
        //    public var hasRecentActivity: Bool {
        //             let level = await InputAudioMonitor.shared.currentLevelDB // ❌ Invalid in sync property
        //             let level = Task.detached(priority: .userInitiated) {
        //                 await InputAudioMonitor.shared.currentLevelDB
        //             }
        //        return !isVirtual && isActive && isSelectable && channelCount > 0 // fallback until refactored
        //    }
    public static var preview: InputAudioDevice {
        InputAudioDevice(id: "preview-id", uid: "preview-uid", name: "🎧 Preview Device", audioObjectID: 1234, channelCount: 2)
    }
}
