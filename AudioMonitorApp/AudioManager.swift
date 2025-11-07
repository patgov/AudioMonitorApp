import Foundation
import Combine
@preconcurrency import AVFoundation
import os
#if os(macOS)
import CoreAudio
#endif
import Accelerate

@MainActor
public final class AudioManager: ObservableObject, AudioManagerProtocol {
    private let logger = Logger(subsystem: "us.govango.AudioMonitorApp", category: "AudioManager")
    
        // Backing storage for protocol Float getters
    private var currentLeftLevel: Float = -120
    private var currentRightLevel: Float = -120
    
        // Input devices stream required by AudioManagerProtocol
    private let inputDevicesSubject = CurrentValueSubject<[InputAudioDevice], Never>([])
    public var inputDevicesStream: AnyPublisher<[InputAudioDevice], Never> { inputDevicesSubject.eraseToAnyPublisher() }
    
        // MARK: - Published Streams
    private let statsSubject = CurrentValueSubject<AudioStats, Never>(.zero)
    
        // Per-channel level streams required by AudioManagerProtocol
    private let leftLevelSubject = CurrentValueSubject<Float, Never>(-120)
    private let rightLevelSubject = CurrentValueSubject<Float, Never>(-120)
    public var leftLevelStream: AnyPublisher<Float, Never> { leftLevelSubject.eraseToAnyPublisher() }
    public var rightLevelStream: AnyPublisher<Float, Never> { rightLevelSubject.eraseToAnyPublisher() }
    
        // Selected device stream required by AudioManagerProtocol
    private let selectedInputDeviceSubject = CurrentValueSubject<InputAudioDevice, Never>(.none)
    public var selectedInputDeviceStream: AnyPublisher<InputAudioDevice, Never> { selectedInputDeviceSubject.eraseToAnyPublisher() }
    
    public var audioStatsStream: AnyPublisher<AudioStats, Never> { statsSubject.eraseToAnyPublisher() }
    
        // Protocol-required current levels (Float getters)
    public var leftLevel: Float { currentLeftLevel }
    public var rightLevel: Float { currentRightLevel }
    
        // MARK: - Engine
        // private var engine: AVAudioEngine?
    private var tapInstalled = false
    private var pendingRestartWork: DispatchWorkItem? = nil
        // Tap/engine retry for transient zero-channel states after route changes
    private var tapRetryCount = 0
    private let tapRetryMax = 10
    private let tapRetryDelay: TimeInterval = 0.25
    private var pendingTapRetry: DispatchWorkItem? = nil
    
        // MARK: - Smoothing & Silence
    private var smoothedLeft: Float = -80
    private var smoothedRight: Float = -80
    private let smoothing: Float = 0.12
        /// Levels below this threshold are treated as silence to avoid false "hot" idles on some devices.
    private let noiseGateDB: Float = -90
    private var silentCount = 0
    
        // Per-device adaptive noise floor (for display/camera/loopback-ish inputs)
    private var learnedNoiseFloor: Float = -120
    private var learnedNoiseFloorSamples: Int = 0
    private let noiseFloorLearnWindow: Int = 50
    private let noiseFloorSlack: Float = 0.8
    
        // Wait before learning noise floor after a route/device change
    private var noiseFloorLearnNotBefore: Date? = nil
    
    
#if !os(macOS)
    private let session = AVAudioSession.sharedInstance()
#endif
    private let engine = AVAudioEngine()
    
        // Tracks whether the app has been granted Mic permission (TCC)
    private var hasMicPermission: Bool = false
    
        // Prevent overlapping graph builds / starts
    private var isStarting = false
    
        // Conservative tap buffer to satisfy devices with small mMaxFramesPerSlice (e.g., 24000–48000 Hz inputs)
    private let tapBufferSize: AVAudioFrameCount = 192
    
        // Normalization for level metering (convert any input to 2ch Float32 @ input sample rate before measuring)
#if os(macOS)
        /// Grace window to ignore rapid successive system-driven input changes (HAL flapping, AirPods reconnects)
    private var inputAutoSelectGraceUntil: Date? = nil
#endif
    private var meterConverter: AVAudioConverter? = nil
    private var meterFormat: AVAudioFormat? = nil
#if os(macOS)
        /// Do NOT force the macOS System Settings default input to our selection unless explicitly enabled.
    private var forceSystemDefaultToSelected = false
        /// Tracks whether we've registered a listener for default input changes.
    private var defaultListenerInstalled = false
        /// Prevent recursive/default-switch feedback loops
    private var isSwitchingDefaultInput = false
        /// Current snapshot of available input devices (computed on demand)
    private var inputDevices: [InputAudioDevice] { enumerateInputDevices() }
        /// Engine restart backoff for transient HAL failures (-10877, server failed to start)
    private var engineRestartRetryCount = 0
    private let engineRestartRetryMax = 5
    private let engineRestartRetryDelay: TimeInterval = 0.6
#endif
    
    public var isRunning: Bool { engine.isRunning }
    
    
    
        // MARK: - Selected Device
    public private(set) var selectedDevice: InputAudioDevice = .none
    
        // MARK: - Public Controls
    public func selectDevice(_ device: InputAudioDevice) {
        DispatchQueue.main.async {
                // Ignore if selecting the same device
            if device.id == self.selectedDevice.id { return }
            
                // Update selection & publish immediately so UI reflects the change
            self.selectedDevice = device
            self.selectedInputDeviceSubject.send(device)
            
                // reset adaptive noise floor when user explicitly picks a new device
            self.learnedNoiseFloor = -120
            self.learnedNoiseFloorSamples = 0
            self.noiseFloorLearnNotBefore = Date().addingTimeInterval(1.0)
            
                // hard-reset metering state so new device doesn't inherit previous levels
            self.smoothedLeft = -80
            self.smoothedRight = -80
            self.currentLeftLevel = -80
            self.currentRightLevel = -80
            self.leftLevelSubject.send(-80)
            self.rightLevelSubject.send(-80)
            
                // Debounce engine restart to avoid thrashing when user scrolls the picker
            self.pendingRestartWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.verifyMicPermissionThen { [weak self] in
                        guard let self = self else { return }
                        if self.engine.isRunning { self.engine.stop() }
                        if self.tapInstalled {
                            self.engine.inputNode.removeTap(onBus: 0)
                            self.tapInstalled = false
                        }
#if os(macOS)
                        if self.forceSystemDefaultToSelected,
                           let def = self.systemDefaultInputDevice(),
                           def.id != device.id {
                            self.switchDefaultInputToSelected()
                        }
#endif
                        self.startEngine()
                    }
                }
            }
            self.pendingRestartWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }
    
    
        /// Ensures we currently have mic permission; if granted, runs `action` on the main thread.
    private func verifyMicPermissionThen(_ action: @MainActor @escaping @Sendable () -> Void) {
#if os(macOS)
        if hasMicPermission {
            Task { @MainActor in action() }
            return
        }
            // Re-check — covers cases where the user granted permission after launch.
        ensureMicPermission { [weak self] granted in
            guard let self = self else { return }
            if granted {
                self.logger.info("✅ Mic permission verified (runtime)")
                Task { @MainActor in action() }
            } else {
                self.logger.error("🚫 Mic permission missing — cannot start engine for new device")
            }
        }
#else
        Task { @MainActor in action() }
#endif
    }
    
    
    public func start() {
        logger.info("▶️ start() called → delegating to startEngine()")
        verifyMicPermissionThen { [weak self] in
            self?.startEngine()
        }
    }
    
    public func stop() {
        engine.stop()
        if self.tapInstalled { self.engine.inputNode.removeTap(onBus: 0); self.tapInstalled = false }
        logger.info("🛑 Audio engine stopped.")
    }
    
        // Optional hook for wiring an external LogManager; satisfies protocol requirement
    func updateLogManager(_ logManager: any LogManagerProtocol) {
            // No-op in this implementation; kept for protocol conformance
    }
    
        // MARK: - Core
        // MARK: - Init
    public init() {
        logger.info("🔧 AudioManager init: engine created")
        
#if os(macOS)
        installDeviceChangeListener()
        installDefaultInputChangeListener()
#endif
        
        ensureMicPermission { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if granted {
                    self.logger.info("✅ Mic permission granted")
                    self.hasMicPermission = true
                    self.refreshInputDevices()
#if os(macOS)
                    if self.selectedDevice == .none, let def = self.systemDefaultInputDevice() {
                        self.selectedDevice = def
                        self.selectedInputDeviceSubject.send(def)
                        self.logger.info("🎯 Adopted system default input on init: \(def.name) [id: \(def.id)]")
                    }
#endif
                    if !self.isStarting { self.startEngine() }
                } else {
                    self.hasMicPermission = false
                    self.logger.error("🚫 Mic permission denied — no input levels until granted")
                    self.refreshInputDevices()
                }
            }
        }
        
            // Retry once if the first fetch races HAL
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.inputDevicesSubject.value.isEmpty {
                    self.logger.warning("🔄 Retrying device fetch after empty result")
                    self.refreshInputDevices()
                }
            }
        }
    }
    
    func startEngine() {
        logger.info("🔈 startEngine()")
        guard !isStarting else {
            logger.debug("⏳ startEngine ignored (already starting)")
            return
        }
        isStarting = true
        defer { isStarting = false }
        
            // Tear down any previous tap/graph safely
        if engine.isRunning { engine.stop() }
            //#if os(macOS)
#if os(macOS)
        if forceSystemDefaultToSelected,
           let def = systemDefaultInputDevice(),
           def.id != selectedDevice.id {
            switchDefaultInputToSelected()
        }
#endif
        let input = engine.inputNode
            // Validate that the current input node exposes at least 1 input channel
        let probeFormat = input.inputFormat(forBus: 0)
        if probeFormat.channelCount == 0 {
            logger.error("❌ Input node reports 0 channels — scheduling engine restart")
            scheduleEngineRestart(reason: "zero-channel input", delay: 0.6)
            return
        }
        input.removeTap(onBus: 0)
        tapInstalled = false
        
            // Configure AVAudioSession only on non‑macOS platforms
#if !os(macOS)
        do {
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .mixWithOthers, .allowBluetooth])
            try session.setActive(true, options: [])
        } catch {
            logger.error("⚠️ AVAudioSession setup failed: \(error.localizedDescription)")
        }
#endif
        
            // Build a minimal live I/O graph so the engine has at least one I/O node
        let mixer = engine.mainMixerNode
        mixer.outputVolume = 0.0 // analysis only; no monitoring
        engine.disconnectNodeInput(mixer)
            // Let AVAudioEngine handle sample-rate/channel conversion between the input node and mixer
        engine.connect(input, to: mixer, format: nil)
        
            // Ensure mixer is connected to output so the render graph pulls samples
        engine.disconnectNodeInput(engine.outputNode)
        engine.connect(mixer, to: engine.outputNode, format: nil)
        
            // Prepare, start, and install the input tap
        engine.prepare()
        do {
            try engine.start()
            let fmt = input.inputFormat(forBus: 0)
            logger.info("🎧 Engine started (\(fmt.channelCount)ch @ \(fmt.sampleRate) Hz)")
        } catch {
            logger.error("❌ Engine failed to start: \(error.localizedDescription)")
            scheduleEngineRestart(reason: "engine start failed: \(error.localizedDescription)")
            return
        }
            // On successful start, clear engine restart backoff
#if os(macOS)
        engineRestartRetryCount = 0
#endif
        
        let tapBlock = makeAudioTap()
        input.installTap(onBus: 0, bufferSize: tapBufferSize, format: nil, block: tapBlock)
        tapInstalled = true
        
            // Reset metering converters so they rebuild on first buffer
        meterConverter = nil
        meterFormat = nil
    }
    
#if os(macOS)
    private func scheduleEngineRestart(reason: String, delay: TimeInterval? = nil) {
        guard engineRestartRetryCount < engineRestartRetryMax else {
            logger.error("🛑 Engine restart retry limit reached — giving up (")
            return
        }
        engineRestartRetryCount += 1
        let d = delay ?? engineRestartRetryDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in
            guard let self = self else { return }
            self.logger.warning("🔁 Restarting audio engine (attempt \(self.engineRestartRetryCount)) – \(reason)")
            self.startEngine()
        }
    }
#endif
    
    private func scheduleTapRetry(reason: String) {
        guard engine.isRunning else { return }
        guard tapRetryCount < tapRetryMax else { return }
        tapRetryCount += 1
        pendingTapRetry?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.logger.warning("🔁 Reinstalling tap (attempt \(self.tapRetryCount)) – \(reason)")
            let input = self.engine.inputNode
            input.removeTap(onBus: 0)
            self.tapInstalled = false
            let tapBlock = self.makeAudioTap()
            input.installTap(onBus: 0, bufferSize: self.tapBufferSize, format: nil, block: tapBlock)
            self.tapInstalled = true
            self.meterConverter = nil
            self.meterFormat = nil
        }
        pendingTapRetry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + tapRetryDelay, execute: work)
    }
    
#if os(macOS)
        /// Returns the selected input device's input volume scalar in [0,1], if available.
        /// If the device does not expose a volume scalar, returns nil so metering proceeds normally.
    private func currentSelectedInputDeviceVolumeScalar() -> Float? {
        let dev = selectedDevice.id
        guard dev != 0 else { return nil }
        let vol: Float32 = 0
        let size = UInt32(MemoryLayout<Float32>.size)
        
        func readVolume(element: UInt32) -> Float32? {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: element
            )
            var tmp = vol
            var tmpSize = size
            let status = AudioObjectGetPropertyData(dev, &addr, 0, nil, &tmpSize, &tmp)
            return status == noErr ? tmp : nil
        }
        
            // Try master first, then channel 1
        if let master = readVolume(element: kAudioObjectPropertyElementMain) { return master }
        if let ch1 = readVolume(element: 1) { return ch1 }
        return nil
    }
#endif
    
    
        // MARK: - Audio Tap
    private func makeAudioTap() -> (AVAudioPCMBuffer, AVAudioTime) -> Void {
        return { [weak self] buffer, _ in
            guard let self = self else { return }
            
            guard buffer.frameLength > 0 else {
                DispatchQueue.main.async { [weak self] in
                    self?.processLevels(left: -120, right: -120)
                }
                return
            }
            
#if os(macOS)
            if let vol = self.currentSelectedInputDeviceVolumeScalar() {
                if vol <= 0.01 {
                        // Device explicitly reports an input volume of ~0 → mute
                    DispatchQueue.main.async { [weak self] in self?.processLevels(left: -120, right: -120) }
                    return
                }
            }
#endif
            
                // Build/refresh a target format that matches the source sample rate and uses up to 2 non-interleaved channels
            let srcFmt = buffer.format
            let targetChannels = min(srcFmt.channelCount, 2)
            if self.meterFormat == nil ||
                self.meterFormat?.sampleRate != srcFmt.sampleRate ||
                self.meterFormat?.channelCount != targetChannels {
                self.meterFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                 sampleRate: srcFmt.sampleRate,
                                                 channels: targetChannels,
                                                 interleaved: false)
                self.meterConverter = nil
            }
            
            let tgtFmt = self.meterFormat!
            if self.meterConverter == nil ||
                self.meterConverter?.inputFormat != srcFmt ||
                self.meterConverter?.outputFormat != tgtFmt {
                self.meterConverter = AVAudioConverter(from: srcFmt, to: tgtFmt)
            }
            
            if self.meterConverter == nil, let tgt = self.meterFormat {
                self.meterConverter = AVAudioConverter(from: srcFmt, to: tgt)
            }
            
            guard let tgtFmt = self.meterFormat else {
                let (l, r) = Self.computeLevels(from: buffer)
                DispatchQueue.main.async { [weak self] in self?.processLevels(left: l, right: r) }
                return
            }
            
                // If source already matches target (Float32, non-interleaved, <=2ch), skip conversion
            let needsConvert = !(srcFmt.commonFormat == .pcmFormatFloat32 &&
                                 srcFmt.isInterleaved == false &&
                                 srcFmt.sampleRate == tgtFmt.sampleRate &&
                                 srcFmt.channelCount <= 2)
            
            var outBuffer: AVAudioPCMBuffer? = nil
            if !needsConvert {
                outBuffer = buffer
            } else if let converter = self.meterConverter {
                let frames = AVAudioFrameCount(min(Int(buffer.frameLength), 2048))
                guard let temp = AVAudioPCMBuffer(pcmFormat: tgtFmt, frameCapacity: frames) else {
                    outBuffer = nil
                        // fall through to publish silence via the guard below
                        // (do not analyze incompatible source buffer)
                    return
                }
                temp.frameLength = frames
                
                var convError: NSError? = nil
                let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }
                _ = converter.convert(to: temp, error: &convError, withInputFrom: inputBlock)
                if convError == nil, temp.frameLength > 0 {
                    outBuffer = temp
                } else {
                        // If conversion fails, do NOT analyze the non-Float source — report silence to avoid bogus highs.
                    outBuffer = nil
                }
            }
            
            guard let out = outBuffer else {
                    // If conversion failed, fall back to analyzing the original buffer so meters stay responsive
                let (fallbackL, fallbackR) = Self.computeLevels(from: buffer)
                DispatchQueue.main.async { [weak self] in self?.processLevels(left: fallbackL, right: fallbackR) }
                return
            }
            let (rawL, rawR) = Self.computeLevels(from: out)
                // Apply a small noise gate so muted/idle inputs don't show as "hot" due to device bias/noise.
            let dBL = (rawL < self.noiseGateDB) ? -120 : rawL
            let dBR = (rawR < self.noiseGateDB) ? -120 : rawR
            DispatchQueue.main.async { [weak self] in
                self?.processLevels(left: dBL, right: dBR)
            }
        }
    }
    
    private static func computeLevels(from buffer: AVAudioPCMBuffer) -> (Float, Float) {
        let n = vDSP_Length(buffer.frameLength)
        let chs = Int(buffer.format.channelCount)
        guard n > 0, chs > 0 else { return (-120, -120) }
        
            // Non-interleaved Float32 fast path
        if buffer.format.commonFormat == .pcmFormatFloat32, buffer.format.isInterleaved == false, let data = buffer.floatChannelData {
                // Variance RMS without modifying source
                // Left
            var meanL: Float = 0
            vDSP_meanv(data[0], 1, &meanL, n)
            var meanSqL: Float = 0
            vDSP_measqv(data[0], 1, &meanSqL, n)
            let varL = max(meanSqL - meanL * meanL, 0)
            let rmsL = sqrtf(varL)
            var dBL = 20 * log10f(max(rmsL, 1e-9))
            dBL = max(-120.0, min(dBL, 0.0))
            
                // Right or mirror mono
            var dBR: Float = dBL
            if chs > 1 {
                let right = data[1]
                var meanR: Float = 0
                vDSP_meanv(right, 1, &meanR, n)
                var meanSqR: Float = 0
                vDSP_measqv(right, 1, &meanSqR, n)
                let varR = max(meanSqR - meanR * meanR, 0)
                let rmsR = sqrtf(varR)
                dBR = 20 * log10f(max(rmsR, 1e-9))
                dBR = max(-120.0, min(dBR, 0.0))
            }
            return (dBL, dBR)
        }
        
            // Interleaved Float32 (or any other format exposed as one AudioBuffer)
        if buffer.format.commonFormat == .pcmFormatFloat32, buffer.format.isInterleaved,
           let abl = buffer.audioBufferList.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self) {
            let stride = chs
                // Left
            var meanL: Float = 0
            vDSP_meanv(abl, vDSP_Stride(stride), &meanL, n)
            var meanSqL: Float = 0
            vDSP_measqv(abl, vDSP_Stride(stride), &meanSqL, n)
            let varL = max(meanSqL - meanL * meanL, 0)
            let rmsL = sqrtf(varL)
            var dBL = 20 * log10f(max(rmsL, 1e-9))
            dBL = max(-120.0, min(dBL, 0.0))
            
                // Right or mirror mono
            var dBR: Float = dBL
            if chs > 1 {
                var meanR: Float = 0
                vDSP_meanv(abl.advanced(by: 1), vDSP_Stride(stride), &meanR, n)
                var meanSqR: Float = 0
                vDSP_measqv(abl.advanced(by: 1), vDSP_Stride(stride), &meanSqR, n)
                let varR = max(meanSqR - meanR * meanR, 0)
                let rmsR = sqrtf(varR)
                dBR = 20 * log10f(max(rmsR, 1e-9))
                dBR = max(-120.0, min(dBR, 0.0))
            }
            return (dBL, dBR)
        }
        
            // No fallback for non-Float32: must be converted before analysis
        
        return (-120, -120)
    }
    
    private func processLevels(left: Float, right: Float) {
        var l = left
        var r = right
        
        let now = Date()
        let canLearnNow = (noiseFloorLearnNotBefore == nil) || (now >= noiseFloorLearnNotBefore!)
        
        if canLearnNow {
                // 1) learn per-device idle floor during the first N buffers
            if learnedNoiseFloorSamples < noiseFloorLearnWindow {
                let candidate = max(l, r)
                if candidate < -30 && candidate > -90 {
                    learnedNoiseFloor = max(learnedNoiseFloor, candidate)
                }
                learnedNoiseFloorSamples += 1
            } else {
                    // 2) after learning, clamp values that hover around that floor to silence
                if l > learnedNoiseFloor - noiseFloorSlack && l < learnedNoiseFloor + noiseFloorSlack {
                    l = -120
                }
                if r > learnedNoiseFloor - noiseFloorSlack && r < learnedNoiseFloor + noiseFloorSlack {
                    r = -120
                }
            }
        }
        
            // existing smoothing logic stays the same
        smoothedLeft  = smoothing * l  + (1 - smoothing) * smoothedLeft
        smoothedRight = smoothing * r  + (1 - smoothing) * smoothedRight
        
        currentLeftLevel = smoothedLeft
        currentRightLevel = smoothedRight
        leftLevelSubject.send(smoothedLeft)
        rightLevelSubject.send(smoothedRight)
        
        let stats = AudioStats(left: smoothedLeft,
                               right: smoothedRight,
                               inputName: selectedDevice.name,
                               inputID: Int(selectedDevice.id))
        statsSubject.send(stats)
        
            // silence watchdog unchanged
        if l <= -119 && r <= -119 {
            silentCount += 1
            if silentCount == 20 {
                logger.warning("🛑 Silent input detected.")
                scheduleTapRetry(reason: "sustained silence")
            }
        } else {
            silentCount = 0
            tapRetryCount = 0
            pendingTapRetry?.cancel(); pendingTapRetry = nil
        }
    }
    
        // MARK: - Device Enumeration & Publishing (moved to class scope)
    private func refreshInputDevices() {
#if os(macOS)
            // If we don’t have TCC approval yet, don’t enumerate or mutate selection
        guard hasMicPermission else {
            logger.warning("🔒 Mic permission not granted — skipping device refresh")
            return
        }
        let devices = enumerateInputDevices()
        inputDevicesSubject.send(devices)
        
        if let grace = inputAutoSelectGraceUntil, grace > Date() {
            logger.info("⏱️ Skipping auto-select (within grace window after system change)")
            return
        }
        
            // Selection policy (race-safe): normalize current selection; treat placeholder (.none or id==0) as no selection
        let current = self.selectedDevice
        let selID = current.id
        
            // No devices at all → publish and retry soon, but DO NOT clear current selection (prevents placeholder churn)
        guard devices.isEmpty == false else {
            logger.error("❌ No devices fetched.")
                // keep current selection; schedule a retry since HAL can race during route changes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.refreshInputDevices()
            }
            return
        }
        
        if selID == 0 { // placeholder / none
            logger.warning("⚠️ Selected device is placeholder — adopting system default or first available")
            if let def = systemDefaultInputDevice(), devices.first(where: { $0.id == def.id }) != nil {
                self.selectedDevice = def
                self.selectedInputDeviceSubject.send(def)
                logger.info("🎯 Using system default input for UI: \(def.name) [id: \(def.id)]")
            } else if let first = devices.first {
                self.selectedDevice = first
                self.selectedInputDeviceSubject.send(first)
                logger.info("🎯 Using first enumerated input for UI: \(first.name) [id: \(first.id)]")
            }
        } else if devices.first(where: { $0.id == selID }) != nil {
                // Keep current if still present
            logger.debug("🔎 Selection still valid: \(current.name) [id: \(selID)]")
        } else {
                // Current disappeared → adopt system default if present, else first
            if let def = systemDefaultInputDevice(), devices.first(where: { $0.id == def.id }) != nil {
                self.selectedDevice = def
                self.selectedInputDeviceSubject.send(def)
                logger.info("🎯 Adopted system default (replacement): \(def.name) [id: \(def.id)]")
            } else if let first = devices.first {
                self.selectedDevice = first
                self.selectedInputDeviceSubject.send(first)
                logger.info("🎯 Adopted first device (replacement): \(first.name) [id: \(first.id)]")
            } else {
                logger.error("❌ No valid input device found for selection.")
            }
        }
#else
            // Non-macOS: optionally populate via AVAudioSession.availableInputs
        inputDevicesSubject.send([])
#endif
    }
    
#if os(macOS)
    private func enumerateInputDevices() -> [InputAudioDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize) == noErr else { return [] }
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize, &ids) == noErr else { return [] }
        
        func inputChannelCount(_ id: AudioObjectID) -> UInt32 {
            var streamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streamAddr, 0, nil, &size) == noErr, size > 0 else { return 0 }
            let buf = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<Int8>.alignment)
            defer { buf.deallocate() }
            guard AudioObjectGetPropertyData(id, &streamAddr, 0, nil, &size, buf) == noErr else { return 0 }
            let abl = buf.bindMemory(to: AudioBufferList.self, capacity: 1).pointee
            var total: UInt32 = 0
            for i in 0..<Int(abl.mNumberBuffers) {
                let b = withUnsafePointer(to: abl) { ptr -> AudioBuffer in
                    let listPtr = UnsafeMutablePointer(mutating: ptr)
                    return listPtr.withMemoryRebound(to: AudioBuffer.self, capacity: Int(abl.mNumberBuffers)) { reb in
                        return reb[i]
                    }
                }
                total += b.mNumberChannels
            }
            return total
        }
        
        func deviceName(_ id: AudioObjectID) -> String {
            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &nameAddr, 0, nil, &nameSize) == noErr else { return "Audio Device" }
            let ptr = UnsafeMutableRawPointer.allocate(byteCount: Int(nameSize), alignment: MemoryLayout<Int8>.alignment)
            defer { ptr.deallocate() }
            guard AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nameSize, ptr) == noErr else { return "Audio Device" }
            return (ptr.bindMemory(to: CFString.self, capacity: 1).pointee as String)
        }
        
        var result: [InputAudioDevice] = []
        for id in ids {
            let ch = inputChannelCount(id)
            guard ch > 0 else { continue }
            let name = deviceName(id)
            result.append(InputAudioDevice(id: id, name: name, channelCount: UInt32(Int(ch))))
        }
        return result
    }
    
    private var deviceListenerInstalled = false
    private func installDeviceChangeListener() {
        guard !deviceListenerInstalled else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let callback: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            DispatchQueue.main.async { [weak self] in
                self?.refreshInputDevices()
            }
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, nil, callback)
        deviceListenerInstalled = true
    }
    
        /// Listen for macOS default input changes (System Settings → Sound → Input). When it changes,
        /// adopt the new system default in-app and retarget the engine/tap, without forcing the system default back.
    private func installDefaultInputChangeListener() {
        guard !defaultListenerInstalled else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let callback: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.refreshInputDevices()
                guard let def = self.systemDefaultInputDevice() else { return }
#if os(macOS)
                if self.forceSystemDefaultToSelected,
                   self.selectedDevice.id != 0 {
                    if def.id != self.selectedDevice.id {
                            // External change detected while we pin system default to our selection → revert system default
                        self.switchDefaultInputToSelected()
                        self.logger.info("🔔 System default input changed externally → reverting to selected: \(self.selectedDevice.name) [id: \(self.selectedDevice.id)]")
                    }
                        // Either way, when forcing, do not adopt the external default.
                    return
                }
#endif
                    // Not forcing: adopt the new system default
                self.selectedDevice = def
                self.selectedInputDeviceSubject.send(def)
                self.logger.info("🔔 System default input changed → adopting: \(def.name) [id: \(def.id)]")
                
                    // reset adaptive noise floor for the new system-selected device
                self.learnedNoiseFloor = -120
                self.learnedNoiseFloorSamples = 0
                self.noiseFloorLearnNotBefore = Date().addingTimeInterval(1.0)
                
                    // hard-reset metering state for system-driven input change
                self.smoothedLeft = -80
                self.smoothedRight = -80
                self.currentLeftLevel = -80
                self.currentRightLevel = -80
                self.leftLevelSubject.send(-80)
                self.rightLevelSubject.send(-80)
                
                self.inputAutoSelectGraceUntil = Date().addingTimeInterval(1.0)
                    // Restart engine permission‑aware to retarget input node and reinstall the tap
                self.pendingTapRetry?.cancel(); self.pendingTapRetry = nil
                self.tapRetryCount = 0
                self.verifyMicPermissionThen { [weak self] in
                    guard let self = self else { return }
                    if self.engine.isRunning { self.engine.stop() }
                    if self.tapInstalled { self.engine.inputNode.removeTap(onBus: 0); self.tapInstalled = false }
                    if !self.isStarting { self.startEngine() }
                }
            }
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, nil, callback)
        defaultListenerInstalled = true
    }
#endif
    
        // MARK: - Permissions
    private func ensureMicPermission(_ done: @escaping @Sendable (Bool) -> Void) {
#if os(macOS)
        let st = AVCaptureDevice.authorizationStatus(for: .audio)
        switch st {
        case .authorized:
            self.hasMicPermission = true
            done(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.hasMicPermission = granted
                    done(granted)
                }
            }
        default:
            self.hasMicPermission = false
            done(false)
        }
#else
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                self.hasMicPermission = granted
                done(granted)
            }
        }
#endif
    }
    
#if os(macOS)
        /// Returns the current system default input device (id + name). Channel count is set to 2 as a safe default.
    private func systemDefaultInputDevice() -> InputAudioDevice? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var devID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devID)
        guard st == noErr, devID != 0 else { return nil }
        
            // Fetch the device name for display
        var nameAddr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var nameSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(devID, &nameAddr, 0, nil, &nameSize) == noErr else {
            return InputAudioDevice(id: devID, name: "Default Input", channelCount: 2)
        }
        let namePtr = UnsafeMutableRawPointer.allocate(byteCount: Int(nameSize), alignment: MemoryLayout<Int8>.alignment)
        defer { namePtr.deallocate() }
        guard AudioObjectGetPropertyData(devID, &nameAddr, 0, nil, &nameSize, namePtr) == noErr else {
            return InputAudioDevice(id: devID, name: "Default Input", channelCount: 2)
        }
        let cfStr = namePtr.bindMemory(to: CFString.self, capacity: 1).pointee
        let name = cfStr as String
        return InputAudioDevice(id: devID, name: name, channelCount: 2)
    }
    
    
    
    private func switchDefaultInputToSelected() {
        let sel = selectedDevice
            // Do not attempt to switch if selection is a placeholder or unknown
        if sel.id == 0 { return }
            // Ensure we only act if the device is in our current list
        if !self.inputDevices.contains(where: { $0.id == sel.id }) { return }
            // Reentrancy guard
        if isSwitchingDefaultInput { return }
        isSwitchingDefaultInput = true
        defer { isSwitchingDefaultInput = false }
            // Check current default to avoid redundant sets
        guard let def = systemDefaultInputDevice(), def.id != sel.id else {
            logger.debug("🔁 System default already \(sel.name) [id: \(sel.id)] — no switch needed")
            return
        }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var newID = sel.id
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &newID)
        let safeName = sel.name, safeId = sel.id
        if status == noErr {
            logger.info("🔀 Default input set to \(safeName) [id: \(safeId)]")
        } else {
            logger.error("❌ Failed to set default input to \(safeName) [id: \(safeId)], status=\(status)")
        }
    }
#endif
    
}
