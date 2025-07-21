/*
 The arc color VU meter scale:
 •    Gray for low-level signals
 •    Orange for moderate
 •    Green for optimal
 •    Red for overmodulation (0 to +3)
 */


import SwiftUI
// import AudioToolbox
import Combine
import AVFoundation
import os

    /// `AudioManager` handles audio input configuration, processing, and publishing real-time audio stats.
    /// It integrates with AVAudioEngine to monitor input, mirrors mono input to stereo,
    /// and emits `AudioStats` via Combine. Supports silence detection, fallback devices,
    /// and widget data publishing via App Group.
public final class AudioManager: ObservableObject, AudioManagerProtocol {
    
    private let logger = Logger(subsystem: "us.govango.AudioMonitorApp", category: "AudioManager")
    private let sharedDefaults = UserDefaults(suiteName: "group.us.govango.AudioMonitorApp")
    
    private var silentBufferCounter = 0
    private var isSilentInputWarningShown = false
    
    private var selectedInputDeviceSubject = CurrentValueSubject<InputAudioDevice, Never>(.none)
    private var inputDevicesSubject = CurrentValueSubject<[InputAudioDevice], Never>([])
    private var selectedDevice: InputAudioDevice = .none
    @MainActor
    private var logManager: LogManagerProtocol?
        // Placeholder for stats subject, to be replaced with real implementation later
    private var statsSubject = CurrentValueSubject<AudioStats, Never>(.zero)
    
    private var audioEngine: AVAudioEngine?
    private let audioProcessor = AudioProcessor()
    private var cancellables = Set<AnyCancellable>()
    
    private var smoothedLeft: Float = -80.0
    private var smoothedRight: Float = -80.0
    private let smoothingFactor: Float = 0.1
    
    public var leftLevel: Float {
        return audioProcessor.currentLeftLevel
    }
    
    public var rightLevel: Float {
        return audioProcessor.currentRightLevel
    }
    
    public var isRunning: Bool {
        return audioEngine?.isRunning ?? false
    }
    
    public var audioStatsStream: AnyPublisher<AudioStats, Never> {
        statsSubject.eraseToAnyPublisher()
    }
    
    public var inputDevicesStream: AnyPublisher<[InputAudioDevice], Never> {
        inputDevicesSubject.eraseToAnyPublisher()
    }
    
    public var selectedInputDeviceStream: AnyPublisher<InputAudioDevice, Never> {
        selectedInputDeviceSubject.eraseToAnyPublisher()
    }
    
        /// Updates the reference to the log manager used for audio event tracking.
    public func updateLogManager(_ logManager: any LogManagerProtocol) {
            // Implementation pending – ensure there's a stored reference if needed
        self.logManager = logManager
    }
    
        /// Selects the audio input device to be used for monitoring.
    public func selectDevice(_ device: InputAudioDevice) {
        selectedDevice = device
        selectedInputDeviceSubject.send(device)
    }
    
        /// Starts the audio engine and installs a tap to capture microphone input.
    public func start() {
            // Refresh devices before proceeding
        refreshAvailableDevices()
        
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" ||
            Bundle.main.bundleIdentifier != "us.govango.AudioMonitorApp" {
            logger.warning("🛑 [Preview Diagnostic] AudioManager.start() was triggered during SwiftUI Preview or in widget/extension context!")
        } else {
            logger.info("✅ [Runtime] AudioManager.start() running in normal app mode.")
        }
        
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
              Bundle.main.bundleIdentifier == "us.govango.AudioMonitorApp" else {
            logger.info("⏸️ Skipping audio engine start in preview or widget mode.")
            return
        }
        
        let engine = AVAudioEngine()
        engine.reset()
        self.audioEngine = engine
        
        audioProcessor.audioStatsStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stats in
                self?.statsSubject.send(stats)
            }
            .store(in: &cancellables)
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        logger.info("🔍 InputNode HW format: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) ch")
        logger.info("🔎 Input format: \(inputFormat)")
        if inputNode.numberOfInputs > 0 {
            inputNode.removeTap(onBus: 0)
        }
        logger.info("🔍 Installing tap BEFORE engine start: \(inputFormat)")
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.processAudio(buffer: buffer)
        }
        
        do {
            try engine.start()
            logger.info("🎧 Audio engine started.")
        } catch {
            logger.error("❌ Engine failed to start: \(error.localizedDescription)")
            return
        }
    }
    
        // MARK: - New processAudio(buffer:) to handle mono/stereo mirroring and fallback
    private func processAudio(buffer: AVAudioPCMBuffer) {
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
            // Frame length check to avoid unnecessary processing
        guard frameLength > 0 else {
            logger.warning("⚠️ Skipping buffer with zero frame length.")
            return
        }
        var left: Float = 0.0
        var right: Float = 0.0
        guard let channelData = buffer.floatChannelData else {
            logger.error("❌ No channel data found in buffer.")
            return
        }
            // --- Diagnostics: Print first few sample values for mono and stereo
        if channelCount == 1 {
            let monoChannel = channelData[0]
            if frameLength >= 3 {
                print("🔍 Mono input samples: \(monoChannel[0]), \(monoChannel[1]), \(monoChannel[2])")
            } else if frameLength > 0 {
                let samples = (0..<frameLength).map { "\(monoChannel[$0])" }.joined(separator: ", ")
                print("🔍 Mono input samples (partial): \(samples)")
            }
        } else if channelCount >= 2 {
            let leftChannel = channelData[0]
            let rightChannel = channelData[1]
            if frameLength >= 3 {
                print("🔍 Stereo input samples — L: \(leftChannel[0]), \(leftChannel[1]), \(leftChannel[2])")
                print("🔍 Stereo input samples — R: \(rightChannel[0]), \(rightChannel[1]), \(rightChannel[2])")
            } else if frameLength > 0 {
                let lSamples = (0..<frameLength).map { "\(leftChannel[$0])" }.joined(separator: ", ")
                let rSamples = (0..<frameLength).map { "\(rightChannel[$0])" }.joined(separator: ", ")
                print("🔍 Stereo input samples — L (partial): \(lSamples)")
                print("🔍 Stereo input samples — R (partial): \(rSamples)")
            }
        }
            // Mirror mono to stereo if needed, using RMS calculation
        if channelCount == 1 {
            let monoChannel = channelData[0]
            var sumSquares: Float = 0.0
            for i in 0..<frameLength {
                let sample = monoChannel[i]
                sumSquares += sample * sample
            }
            let rms = sqrt(sumSquares / Float(frameLength))
            left = rms
            right = rms
        } else if channelCount >= 2 {
            let leftChannel = channelData[0]
            let rightChannel = channelData[1]
            var sumLeft: Float = 0.0
            var sumRight: Float = 0.0
            for i in 0..<frameLength {
                sumLeft += leftChannel[i] * leftChannel[i]
                sumRight += rightChannel[i] * rightChannel[i]
            }
            left = sqrt(sumLeft / Float(frameLength))
            right = sqrt(sumRight / Float(frameLength))
        }
            // Convert RMS to dBFS, clamp to -80 dB minimum
        if left > 0 {
            left = 20 * log10(left)
        } else {
            left = -80.0
        }
        if right > 0 {
            right = 20 * log10(right)
        } else {
            right = -80.0
        }
            // Noise gate: suppress near-zero background noise (stricter gating threshold)
        if left < -90.0 { left = -80.0 }
        if right < -90.0 { right = -80.0 }
        left = max(left, -80.0)
        right = max(right, -80.0)
            // Log dB levels and print left sample
        logger.info("🎚️ AudioProcessor - dB levels → Left: \(left), Right: \(right), Device: \(self.selectedDevice.name) [\(self.selectedDevice.id)]")
        print("🔊 First sample (L): \(left)")
        self.audioProcessor.process(buffer: buffer,
                                    inputName: self.selectedDevice.name,
                                    inputID: Int(self.selectedDevice.audioObjectID))
            // Silence detection and fallback logic
        smoothedLeft = smoothingFactor * left + (1 - smoothingFactor) * smoothedLeft
        smoothedRight = smoothingFactor * right + (1 - smoothingFactor) * smoothedRight
            // Additional forced silence floor after smoothing
        if left <= -79.5 {
            smoothedLeft = -80.0
        }
        if right <= -79.5 {
            smoothedRight = -80.0
        }
        let stats = AudioStats(left: smoothedLeft, right: smoothedRight, inputName: selectedDevice.name, inputID: Int(selectedDevice.audioObjectID))
        let previous = statsSubject.value
        if abs(previous.left - stats.left) > 0.01 || abs(previous.right - stats.right) > 0.01 {
            statsSubject.send(stats)
        }
        writeStatsToSharedDefaults(stats)
        if stats.left <= -80.0 && stats.right <= -80.0 {
            guard silentBufferCounter > 5 else { return }
            self.logger.warning("No audio detected on current device. Attempting fallback.")
            self.tryFallbackDevice()
        }
        let isSilent = left <= -79.9 && right <= -79.9
        if isSilent {
            silentBufferCounter += 1
            if silentBufferCounter > 20 && !isSilentInputWarningShown {
                logger.warning("🛑 Warning: Silent input detected — input device is streaming silence.")
                isSilentInputWarningShown = true
            }
        } else {
            silentBufferCounter = 0
            isSilentInputWarningShown = false
        }
    }
    
        // MARK: - Fallback device logic
    private func tryFallbackDevice() {
        let devices = self.availableDevices
        for device in devices {
            self.selectDevice(device)
            self.start()
            if self.leftLevel > -80.0 || self.rightLevel > -80.0 {
                logger.info("Fallback device \(device.name) is capturing audio.")
                break
            }
        }
    }
    
        /// Stops the audio engine and removes any active taps.
    public func stop() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        logger.info("🛑 Audio engine stopped.")
    }
    
    
    
    
    private func refreshAvailableDevices() {
        guard Bundle.main.bundleIdentifier == "us.govango.AudioMonitorApp" else {
            logger.info("⏸️ Skipping device refresh outside main app.")
            return
        }
#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        let devices = session.availableInputs?.map {
            InputAudioDevice(id: $0.uid, name: $0.portName)
        } ?? []
        inputDevicesSubject.send(devices)
        logger.info("🔄 Available devices: \(devices.map { $0.name })")
#else
            // macOS (not Catalyst): fetch live devices using Core Audio utilities.
        let allDevices = InputAudioDevice.fetchAvailableDevices()
            .filter { $0.channelCount > 0 }
            .map { device in
                InputAudioDevice(
                    id: device.id,
                    uid: device.uid,
                    name: device.name,
                    audioObjectID: device.audioObjectID,
                    channelCount: device.channelCount
                )
            }
        
        print("🛠️ All discovered devices: \(allDevices.map { $0.displayName })")
        logger.info("🔄 Available devices: \(allDevices.map { "\($0.name) [\($0.channelCount)ch]" })")
        
        _ = InputAudioDevice.fetchDefaultInputDeviceID()
        
        inputDevicesSubject.send([.none] + allDevices)
        
        if selectedDevice == InputAudioDevice.none || !allDevices.contains(selectedDevice) {
                // Prefer devices with more than 1 channel and without known virtual/poor-quality identifiers
            let preferred = allDevices.first {
                let name = $0.name.lowercased()
                let isVirtual = name.contains("blackhole") || name.contains("display") || name.contains("airpods") || name.contains("camera") || name.contains("parallels")
                return !isVirtual && $0.channelCount >= 1
            } ?? allDevices.first
            
            if let autoSelect = preferred {
                self.selectedDevice = autoSelect
                print("🎯 Auto-selected preferred device: \(autoSelect.name) [\(autoSelect.id)]")
            }
        }
#endif
    }
    
        // MARK: - Helper to get current available devices
    private var availableDevices: [InputAudioDevice] {
        var devices: [InputAudioDevice] = []
#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        devices = session.availableInputs?.map {
            InputAudioDevice(id: $0.uid, name: $0.portName)
        } ?? []
#else
        devices = InputAudioDevice.fetchAvailableDevices()
            .filter { $0.channelCount > 0 }
            // Exclude .none
        devices = devices.filter { $0 != InputAudioDevice.none }
#endif
        return devices
    }
    
    private func writeStatsToSharedDefaults(_ stats: AudioStats) {
        do {
            let data = try JSONEncoder().encode(stats)
            sharedDefaults?.set(data, forKey: "latestAudioStats")
        } catch {
            logger.error("❌ Failed to encode AudioStats for widget: \(error.localizedDescription)")
        }
    }
}
