    //
    //  AudioManager.swift
    //  AudioMonitorApp
    //
    //  Created by Pat Govan on 3/19/25.
    //

import Foundation
import AVFoundation
import CoreAudio
import Combine
import Accelerate

class AudioManager: ObservableObject {
    @Published var leftLevel: Float = -80
    @Published var rightLevel: Float = -80

    private let engine = AVAudioEngine()
    private var inputNode: AVAudioInputNode?

    private(set) var processor: AudioProcessor
    private let logManager: LogManager

    init(processor: AudioProcessor, logManager: LogManager) {
        self.processor = processor
        self.logManager = logManager

        processor.$leftLevel.assign(to: &$leftLevel)
        processor.$rightLevel.assign(to: &$rightLevel)


        func triggerMicrophoneAccessRequest() {
            let session = AVCaptureSession()
            guard let device = AVCaptureDevice.default(for: .audio) else { return }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                    session.startRunning()
                    session.stopRunning()
                }
            } catch {
                print("❌ Error triggering mic access: \(error)")
            }
        }

    }

    private func installTap() {
        inputNode = engine.inputNode

            // Make sure the node has no existing tap before installing
        inputNode?.removeTap(onBus: 0)

        let format = inputNode?.inputFormat(forBus: 0)
        ?? AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        print("🎚 Input format: \(format)")

        inputNode?.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }

            let frameCount = Int(buffer.frameLength)
            let left = self.meterLevel(from: channelData[0], count: frameCount)
            let right = buffer.format.channelCount > 1
            ? self.meterLevel(from: channelData[1], count: frameCount)
            : left

            DispatchQueue.main.async {
                self.processor.leftLevel = left
                self.processor.rightLevel = right
                self.processor.process(buffer: buffer)
                self.logManager.processLevel(left, channel: 0)
                self.logManager.processLevel(right, channel: 1)
                print("🎚 Left level: \(left), Right level: \(right)")
            }
        }

        print("📡 Tap installed on input node.")
    }

    func start() {
        autoSelectBestInputDevice()
        installTap()

        do {
            try engine.start()
            print("🎧 Audio engine started.")
        } catch {
            print("❌ Failed to start audio engine: \(error)")
        }
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        print("🛑 Audio engine stopped.")
    }



    private func meterLevel(from channel: UnsafePointer<Float>, count: Int) -> Float {
        var sum: Float = 0
        vDSP_measqv(channel, 1, &sum, vDSP_Length(count))
        let rms = sqrt(sum)
        let level = 20 * log10(rms)
        return max(level, -80)
    }

    func autoSelectBestInputDevice() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )

        guard status == noErr else { return }

        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.size
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioDeviceID>.alignment
        )
        defer { buffer.deallocate() }

        let fetchStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            buffer
        )

        guard fetchStatus == noErr else { return }

        let deviceIDs = buffer.bindMemory(to: AudioDeviceID.self, capacity: deviceCount)

        for index in 0..<deviceCount {
            let deviceID = deviceIDs[index]
            if let name = getDeviceName(for: deviceID)?.lowercased() {
                    // Skip known problematic or virtual devices
                if name.contains("AK4571") || name.contains("raw") || name.contains("lg") {
                    continue
                }

                    // Prefer built-in or USB microphones
                if name.contains("mic") || name.contains("built-in") || name.contains("usb") {
                    print("🎤 Auto-selected input: \(name)")
                    setInputDevice(deviceID)
                    return
                }
            }
        }
    }
    
    private func getDeviceName(for deviceID: AudioDeviceID) -> String? {
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var unmanagedName: Unmanaged<CFString>?

        let status = withUnsafeMutablePointer(to: &unmanagedName) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: Int(size)) { rawPtr in
                AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &size, rawPtr)
            }
        }

        if status == noErr, let cfName = unmanagedName?.takeRetainedValue() {
            return cfName as String
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

    private func debugPrintAvailableInputDevices() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        guard status == noErr else {
            print("❌ Failed to get device data size")
            return
        }

        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.size
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioDeviceID>.alignment)
        defer { buffer.deallocate() }

        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, buffer)
        guard status == noErr else {
            print("❌ Failed to get device data")
            return
        }

        let deviceIDs = buffer.bindMemory(to: AudioDeviceID.self, capacity: deviceCount)
        for i in 0..<deviceCount {
            let id = deviceIDs[i]
            if let name = getDeviceName(for: id) {
                print("🎙 Device [\(i)]: \(name) [ID: \(id)]")
            }
        }
    }

}


extension AudioManager {
    func requestPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                if !engine.isRunning {
                    start()
                }
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        if granted {
                            self.start()
                        } else {
                            print("❌ Microphone permission denied")
                        }
                    }
                }
            default:
                print("❌ Microphone access denied or restricted")
        }
    }

}
