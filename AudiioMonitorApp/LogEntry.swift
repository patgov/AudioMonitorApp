    //  LogEntry.swift
    //  AudiioMonitorApp
    //
    //  Created by Pat Govan on 4/5/25.
    //

import Foundation

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: String
    let source: String
    let message: String
    let channel: Int
    let value: Float
}
