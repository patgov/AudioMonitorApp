    //
    //  AudioEngineHandler.swift.swift
    //  AudiioMonitorApp
    //
    //  Created by Pat Govan on 5/12/25.
    //

import Foundation
import AVFoundation
import CoreAudio

    /// Handles audio engine setup, input format configuration, and buffer tap installation.


class AudioEngineHandler {
    private var audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode?
    private var bufferSize: AVAudioFrameCount = 1024
    
    func configureAudioInput(completion: @escaping (String?) -> Void) {
            // macOS-compatible input device detection
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceID
        )
        
        guard status == noErr else {
            completion(nil)
            return
        }
        
        var nameSize: UInt32 = 0
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
            // First, determine the size of the name data
        let nameSizeStatus = AudioObjectGetPropertyDataSize(deviceID, &nameAddress, 0, nil, &nameSize)
        guard nameSizeStatus == noErr else {
            completion(nil)
            return
        }
        
        let namePtr = UnsafeMutableRawPointer.allocate(byteCount: Int(nameSize), alignment: MemoryLayout<CFString>.alignment)
        defer {
            namePtr.deallocate()
        }
        
        let nameStatus = AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, namePtr)
        guard nameStatus == noErr else {
            completion(nil)
            return
        }
        
        let name = namePtr.load(as: CFString.self)
        completion(name as String)
    }
    
    func setupTap(onBuffer: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void) {
        inputNode = audioEngine.inputNode
        let inputFormat = inputNode!.outputFormat(forBus: 0)
        
        let stereoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: 2,
            interleaved: false
        )
        
        inputNode?.installTap(onBus: 0, bufferSize: bufferSize, format: stereoFormat) { buffer, time in
            print("📡 Audio buffer received — Frame length: \(buffer.frameLength)")
            onBuffer(buffer, time)
        }
    }
    
    func start() throws {
        try audioEngine.start()
    }
    
    func stop() {
        inputNode?.removeTap(onBus: 0)
        audioEngine.stop()
    }
}
