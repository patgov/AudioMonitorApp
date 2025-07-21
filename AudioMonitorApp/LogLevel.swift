    //
    //  logLevel.swift
    //  AudioMonitorApp
    //
    //  Created by Pat Govan on 6/11/25.
    //

import Foundation


enum LogLevel: String, CaseIterable, Codable {
    case debug
    case info
    case warning
    case error
    case critical
}

import SwiftUI

extension LogLevel {
    var symbol: String {
        switch self {
            case .debug: return "ladybug"
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.octagon"
            case .critical: return "flame"
        }
    }
    
    var color: Color {
        switch self {
            case .debug: return .gray
            case .info: return .blue
            case .warning: return .yellow
            case .error: return .orange
            case .critical: return .red
        }
    }
}
