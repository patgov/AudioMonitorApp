import CoreAudio
import Foundation

public struct InputAudioDevice: Hashable, Comparable, CustomStringConvertible {
    public let id: AudioObjectID
    public let name: String
    public let channelCount: UInt32
    
    @MainActor public static let none = InputAudioDevice(id: 0, name: "None", channelCount: 0)
    
    public var displayName: String {
        channelCount > 0 ? "\(name) · \(channelCount)ch" : name
    }
    
    public var isSelectable: Bool { channelCount > 0 && id != AudioObjectID(0) }
    public var isBlackHole: Bool { name.localizedCaseInsensitiveContains("blackhole") }
    public var isVirtual: Bool {
        let n = name.lowercased()
        return n.contains("aggregate") || n.contains("loopback") || n.contains("virtual")
    }
    public var hasRecentActivity: Bool { false }
    public var isSystemDefault: Bool { name.lowercased().contains("default") || id == AudioObjectID(0) }
    
    public var description: String { "\(name) [id: \(id)] \(channelCount)ch" }
    
    public static func < (lhs: InputAudioDevice, rhs: InputAudioDevice) -> Bool {
        let cmp = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if cmp != .orderedSame { return cmp == .orderedAscending }
        if lhs.channelCount != rhs.channelCount { return lhs.channelCount < rhs.channelCount }
        return lhs.id < rhs.id
    }
}


