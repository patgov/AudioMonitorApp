//
//  AudioLogEntry..swift
//  AudiioMonitorApp
//
//Define the structure for each individual log entry in the app
// Represent one event or log record, such as a silence, overmodulation, or info message.
// Standardize the log format for display, filtering, exporting, or storage.
// Support computed properties or factory methods (e.g., AudioLogEntry.warning(...)) to simplify log creation across the app.
//

import Foundation
import SwiftUI


import Foundation

public struct AudioLogEntry: Identifiable, Hashable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let level: String
    public let source: String
    public let message: String
    public let channel: Int
    public let value: Float
    public let inputName: String
    public let inputID: Int

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: String,
        source: String,
        message: String,
        channel: Int,
        value: Float,
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

    public static func info(_ message: String, channel: Int = -1, value: Float = 0.0, inputName: String = "", inputID: Int = 0, source: String = "System") -> AudioLogEntry {
        AudioLogEntry(level: "INFO", source: source, message: message, channel: channel, value: value, inputName: inputName, inputID: inputID)
    }

    public static func warning(_ message: String, channel: Int = -1, value: Float = 0.0, inputName: String = "", inputID: Int = 0, source: String = "System") -> AudioLogEntry {
        AudioLogEntry(level: "WARNING", source: source, message: message, channel: channel, value: value, inputName: inputName, inputID: inputID)
    }

    public static func error(_ message: String, channel: Int = -1, value: Float = 0.0, inputName: String = "", inputID: Int = 0, source: String = "System") -> AudioLogEntry {
        AudioLogEntry(level: "ERROR", source: source, message: message, channel: channel, value: value, inputName: inputName, inputID: inputID)
    }
}

