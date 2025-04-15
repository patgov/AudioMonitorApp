    //
    //  AudioMonitorViewModel.swift
    //  AudiioMonitorApp
    //
    //  Created by Pat Govan on 4/9/25.
    //

import Foundation
import SwiftUI
import Combine

@MainActor
class AudioMonitorViewModel: ObservableObject {
    @ObservedObject var processor: AudioProcessor

    @Published var leftLevel: Float = -80.0
    @Published var rightLevel: Float = -80.0

    @Published var isSilent: Bool = false
    @Published var isOvermodulated: Bool = false
    @Published var statusText: String = "Initializing..."
    @Published var statusColor: Color = .gray
    @Published var logEntries: [LogEntry] = []

    private var cancellables: Set<AnyCancellable> = []

    let audioManager: AudioManager
    let logManager: LogManager
    
    var exposedLogManager: LogManager? {
        return logManager
    }
    init(audioManager: AudioManager, logManager: LogManager) {
        self.audioManager = audioManager
        self.logManager = logManager
        self.processor = audioManager.processor
    }

    func start() {
        audioManager.start()
    }

    func stop() {
        audioManager.stop()
    }

    func bindToAudioProcessor() {
        audioManager.processor.$leftLevel
            .receive(on: DispatchQueue.main)
            .assign(to: &$leftLevel)

        audioManager.processor.$rightLevel
            .receive(on: DispatchQueue.main)
            .assign(to: &$rightLevel)

        audioManager.processor.$isSilent
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isSilent in
                self?.isSilent = isSilent
                self?.updateStatus()
            }
            .store(in: &cancellables)

        audioManager.processor.$isOvermodulated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOvermodulated in
                self?.isOvermodulated = isOvermodulated
                self?.updateStatus()
            }
            .store(in: &cancellables)
    }

    private func updateStatus() {
        if isOvermodulated {
            statusText = "🔴 Overmodulated"
            statusColor = .red
        } else if isSilent {
            statusText = "🟡 Silent"
            statusColor = .yellow
        } else {
            statusText = "🟢 Normal"
            statusColor = .green
        }
    }

    func loadLogData() {
        Task {
            let loaded = await logManager.loadLogEntries()
            await MainActor.run {
                self.logEntries = loaded
            }
        }
    }
}
