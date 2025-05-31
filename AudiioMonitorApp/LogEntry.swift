import Foundation

public struct LogEntry: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var level: String   // e.g., "INFO", "WARNING", "ERROR"
    public var source: String  // e.g., "AudioProcessor", "LogManager"
    public var message: String
    public var channel: Int?   // 0 = Left, 1 = Right, nil = Global
    public var value: Float?   // e.g., dB value at time of event
    public var inputName: String
    public var inputID: Int

    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        level: String,
        source: String,
        message: String,
        channel: Int? = nil,
        value: Float? = nil,
        inputName: String,
        inputID: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.source = source
        self.message = message
        self.channel = channel
        self.value = value
        self.inputName = inputName
        self.inputID = inputID
    }

    public static var preview: LogEntry {
        LogEntry(
            level: "INFO",
            source: "MockAudioManager",
            message: "Preview log entry for UI testing",
            channel: 0,
            value: -24.7,
            inputName: "Preview Mic",
            inputID: 101
        )
    }
}


