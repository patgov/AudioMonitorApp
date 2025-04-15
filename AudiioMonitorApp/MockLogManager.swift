//
//  MockLogManager.swift
//  AudiioMonitorApp
//
//  Created by Pat Govan on 4/11/25.
//

import SwiftUI

class MockLogManager: ObservableObject {
        // add only what’s needed for preview
    @Published var stats = AudioStats(from: Date())
}
