import Foundation

public struct AudioStats: Codable, Equatable, Hashable, Sendable {
    public var left: Float
    public var right: Float
    public var inputName: String
    public var inputID: Int
    
    public var timestamp: Date
    public var overmodulationCount: Int
    public var silenceCount: Int
    
    public init(
        left: Float,
        right: Float,
        inputName: String,
        inputID: Int,
        timestamp: Date = .now,
        overmodulationCount: Int = 0,
        silenceCount: Int = 0
    ) {
        self.left = left
        self.right = right
        self.inputName = inputName
        self.inputID = inputID
        self.timestamp = timestamp
        self.overmodulationCount = overmodulationCount
        self.silenceCount = silenceCount
    }
    
    public static var zero: AudioStats {
        AudioStats(left: -80.0, right: -80.0, inputName: "None", inputID: 0)
    }
    
    public static var preview: AudioStats {
        AudioStats(left: -22.5, right: -21.3, inputName: "Mock Mic", inputID: 1)
    }
}

public extension AudioStats {
    var leftVU: Float {
        Self.dbToVU(left)
    }
    
    var rightVU: Float {
        Self.dbToVU(right)
    }
    
    static func dbToVU(_ db: Float) -> Float {
        let minDB: Float = -60
        let maxDB: Float = 0
        let clamped = max(min(db, maxDB), minDB) // Clamp to [-60, 0]
        let normalized = (clamped - minDB) / (maxDB - minDB) // Range [0, 1]
        return normalized * 100 // Convert to 0–100 scale
    }
}
