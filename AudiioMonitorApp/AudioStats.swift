//
//  AudioStats.swift
//  AudiioMonitorApp
//
//  Created by Pat Govan on 4/11/25.
//

import SwiftUI
import Foundation

struct AudioStats {
    var silenceCountLeft: [Int]
    var silenceCountRight: [Int]
    var overmodulationCountLeft: [Int]
    var overmodulationCountRight: [Int]

    var startTime: Date

    init(from date: Date) {
        self.startTime = date
        self.silenceCountLeft = []
        self.silenceCountRight = []
        self.overmodulationCountLeft = []
        self.overmodulationCountRight = []
    }

    mutating func recordSilence(channel: Int, timestamp: Date) {
        if channel == 0 {
            silenceCountLeft.append(Int(timestamp.timeIntervalSince(startTime)))
        } else if channel == 1 {
            silenceCountRight.append(Int(timestamp.timeIntervalSince(startTime)))
        }
    }

    mutating func recordOvermodulation(channel: Int, timestamp: Date) {
        if channel == 0 {
            overmodulationCountLeft.append(Int(timestamp.timeIntervalSince(startTime)))
        } else if channel == 1 {
            overmodulationCountRight.append(Int(timestamp.timeIntervalSince(startTime)))
        }
    }

    mutating func reset(from date: Date) {
        self = AudioStats(from: date)
    }
}
