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


