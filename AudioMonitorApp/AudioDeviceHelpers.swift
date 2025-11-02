//
//  AudioDeviceHelpers.swift
//  AudioMonitorApp
//
//  Created by Pat Govan on 8/11/25.
//

import Foundation
import CoreAudio
import AudioToolbox

    // Internal, namespaced helpers so they don't collide with anything else.
enum AudioDeviceHelpers {
    
    static func getDeviceName(_ id: AudioObjectID) -> String {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfName: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let err = withUnsafeMutablePointer(to: &cfName) { p in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, p)
        }
        return (err == noErr) ? (cfName as String) : "Unknown"
    }
    
    static func deviceIsAlive(_ id: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &alive) == noErr && alive != 0
    }
    
    static func inputChannelCount(_ id: AudioObjectID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(id, &addr) else { return 0 }
        
        var byteSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &byteSize) == noErr,
              byteSize >= UInt32(MemoryLayout<AudioBufferList>.size) else { return 0 }
        
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(byteSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        
        let abl = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &byteSize, abl) == noErr else { return 0 }
        
        var total: UInt32 = 0
        for buf in UnsafeMutableAudioBufferListPointer(abl) {
            total &+= buf.mNumberChannels
        }
        return total
    }
    
    static func defaultInputDeviceID() -> AudioObjectID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var def: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                             &addr, 0, nil, &size, &def)
        return (err == noErr && def != 0) ? def : nil
    }
}
        extension AudioDeviceHelpers {
            static func availableInputDevices() -> [InputAudioDevice] {
                var addr = AudioObjectPropertyAddress(
                    mSelector: kAudioHardwarePropertyDevices,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                
                var byteSize: UInt32 = 0
                guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &byteSize) == noErr else {
                    return []
                }
                
                let count = Int(byteSize) / MemoryLayout<AudioObjectID>.size
                var ids = [AudioObjectID](repeating: 0, count: count)
                guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &byteSize, &ids) == noErr else {
                    return []
                }
                
                var out: [InputAudioDevice] = []
                out.reserveCapacity(ids.count)
                
                for id in ids {
                    guard deviceIsAlive(id) else { continue }
                    let ch = inputChannelCount(id)
                    guard ch > 0 else { continue }
                    let name = getDeviceName(id)
                    out.append(InputAudioDevice(id: id, name: name, channelCount: ch))
                }
                
                    // Optional: put default input first
                if let def = defaultInputDeviceID(), let i = out.firstIndex(where: { $0.id == def }) {
                    let d = out.remove(at: i)
                    out.insert(d, at: 0)
                }
                return out
            }
        }
        
