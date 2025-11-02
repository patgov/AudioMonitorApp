    //
    //  AudioManagerEnvironmentKeys.swift
    //  AudioMonitorApp
    //
    //  Created by Pat Govan on 6/11/25.
    //

import SwiftUI

    // MARK: - AudioManager EnvironmentKey
private struct AudioManagerKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: AudioManagerProtocol = MainActor.assumeIsolated {
        DummyAudioManager()
    }
}

extension EnvironmentValues {
    var audioManager: AudioManagerProtocol {
        get { self[AudioManagerKey.self] }
        set { self[AudioManagerKey.self] = newValue }
    }
}

    // MARK: - LogManager EnvironmentKey
private struct LogManagerKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: LogManagerProtocol = MainActor.assumeIsolated {
        DummyLogManager()
    }
}

extension EnvironmentValues {
    var logManager: LogManagerProtocol {
        get { self[LogManagerKey.self] }
        set { self[LogManagerKey.self] = newValue }
    }
}
