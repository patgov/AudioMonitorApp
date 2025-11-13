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
    private let rawLeftLevelSubject = CurrentValueSubject<Float, Never>(-120)
    private let rawRightLevelSubject = CurrentValueSubject<Float, Never>(-120)
    private let isGatedSubject = CurrentValueSubject<Bool, Never>(false)
    public var leftLevelStream: AnyPublisher<Float, Never> { leftLevelSubject.eraseToAnyPublisher() }
    public var rightLevelStream: AnyPublisher<Float, Never> { rightLevelSubject.eraseToAnyPublisher() }
    public var rawLeftLevelStream: AnyPublisher<Float, Never> { rawLeftLevelSubject.eraseToAnyPublisher() }
    public var rawRightLevelStream: AnyPublisher<Float, Never> { rawRightLevelSubject.eraseToAnyPublisher() }
    public var isGatedStream: AnyPublisher<Bool, Never> { isGatedSubject.eraseToAnyPublisher() }
    
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
    private let noiseGateDB: Float = -95
    private var silentCount = 0
    
        // Per-device adaptive noise floor (for display/camera/loopback-ish inputs)
    private var learnedNoiseFloor: Float = -120
    private var learnedNoiseFloorSamples: Int = 0
    private let noiseFloorLearnWindow: Int = 50
    private let noiseFloorSlack: Float = 1.5
    
        // Cooldown so display/Ultrafine mics don't get reclamped immediately after real activity
    private var displayActivityCooldown: Int = 0
    
        // Short hold to ignore periodic downward pulses on display/LG mics
    private var displayPulseHoldFrames: Int = 0
    private let displayPulseHoldMax: Int = 5
    
        // When we detect real speech on display/LG mics, keep gating disabled briefly
    private var displayTalkingFrames: Int = 0
    
        // Ignore backward pulses while talking on display/LG mics
    private let displayDropIgnoreThreshold: Float = 6.0
    
        // Frame counter since engine start (for device-specific stabilization)
    private var framesSinceEngineStart: Int = 0
    
        // Tracks if last frame was gated (for UI/diagnostics)
    private var lastFrameWasGated: Bool = false
    
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
    
        /// Debug helper: describes the current metering converter, if any
    public var meterConverterInfo: String {
        guard let converter = meterConverter else { return "meterConverter = nil" }
        let inFmt = converter.inputFormat
        let outFmt = converter.outputFormat
        return "meterConverter: \(inFmt.sampleRate) Hz / \(inFmt.channelCount) ch → \(outFmt.sampleRate) Hz / \(outFmt.channelCount) ch"
    }
    
        /// Manually reset the metering pipeline so the next audio buffer rebuilds it
    public func resetMeteringPipeline() {
        meterConverter = nil
        meterFormat = nil
        logger.info("🧹 Metering pipeline reset — will rebuild on next tap buffer")
    }
    
    
    
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
            
                // reset per-device transient state so the previous device's silence/tap state doesn't leak
            self.silentCount = 0
            self.tapRetryCount = 0
            self.pendingTapRetry?.cancel()
            self.pendingTapRetry = nil
            
                // push UI to a known quiet state while the engine retargets
            self.smoothedLeft = -120
            self.smoothedRight = -120
            self.currentLeftLevel = -120
            self.currentRightLevel = -120
            self.leftLevelSubject.send(-120)
            self.rightLevelSubject.send(-120)
            
                // reset adaptive noise floor when user explicitly picks a new device
            self.learnedNoiseFloor = -120
            self.learnedNoiseFloorSamples = 0
            self.noiseFloorLearnNotBefore = Date().addingTimeInterval(1.0)
            
            
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
            
                // Fragile, continuity-style devices (iPhone, Lumina/camera) often come up in two phases:
                // 1) placeholder/None, then 2) the real 1–2ch stream a moment later.
                // The first restart above may bind to the placeholder; schedule a follow-up restart
                // to retarget the real stream once it has appeared.
            let lower = device.name.lowercased()
            if lower.contains("iphone") || lower.contains("lumina") || lower.contains("camera") {
                let followup = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                        // Only do this if the user is still on this device
                    if self.selectedDevice.id != device.id { return }
                    self.verifyMicPermissionThen { [weak self] in
                        guard let self = self else { return }
                        if self.engine.isRunning { self.engine.stop() }
                        if self.tapInstalled {
                            self.engine.inputNode.removeTap(onBus: 0)
                            self.tapInstalled = false
                        }
                        self.startEngine()
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: followup)
            }
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
            
                // reset meter only after we actually have a running engine on the new device
            self.smoothedLeft = -80
            self.smoothedRight = -80
            self.currentLeftLevel = -80
            self.currentRightLevel = -80
            self.leftLevelSubject.send(-80)
            self.rightLevelSubject.send(-80)
            self.framesSinceEngineStart = 0
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
            // capture the device we had when we installed the tap
        let tapDeviceID = self.selectedDevice.id
        let tapDeviceNameLower = self.selectedDevice.name.lowercased()
        
        return { [weak self] buffer, _ in
            guard let self = self else { return }
            
                // if the user changed mics after we installed this tap, ignore this buffer
            if self.selectedDevice.id != tapDeviceID {
                return
            }
            
                // use the captured name so classification stays consistent
            let lowerName = tapDeviceNameLower
            
                // ... rest of your existing tap code, but remove the old line:
                // let lowerName = self.selectedDevice.name.lowercased()
            
            guard buffer.frameLength > 0 else {
                DispatchQueue.main.async { [weak self] in
                    self?.processLevels(left: -120, right: -120)
                }
                return
            }
            
                //#if os(macOS)
#if os(macOS)
            let skipVolumeMute =
            lowerName.contains("lumina") ||
            lowerName.contains("camera") ||
            lowerName.contains("ak4571") ||
            lowerName.contains("iphone") ||
            lowerName.contains("microphone")
            if !skipVolumeMute, let vol = self.currentSelectedInputDeviceVolumeScalar() {
                if vol <= 0.01 {
                        // Device explicitly reports an input volume of ~0 → mute
                    DispatchQueue.main.async { [weak self] in
                        self?.processLevels(left: -120, right: -120)
                    }
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
                let (fallbackL, fallbackR) = Self.computeLevelsFallback(from: buffer)
                DispatchQueue.main.async { [weak self] in
                    self?.processLevels(left: fallbackL, right: fallbackR)
                }
                return
            }
            
            let (rawL, rawR) = Self.computeLevels(from: out)
                // Forward raw (ungated) levels to the new subjects before gating/processing
            DispatchQueue.main.async { [weak self] in
                self?.rawLeftLevelSubject.send(rawL)
                self?.rawRightLevelSubject.send(rawR)
            }
            let skipGate =
            lowerName.contains("ak4571") ||
            lowerName.contains("iphone") ||
            lowerName.contains("microphone")
            let dBL: Float
            let dBR: Float
            if skipGate {
                dBL = rawL
                dBR = rawR
            } else {
                    // Apply a small noise gate so muted/idle inputs don't show as "hot" due to device bias/noise.
                dBL = (rawL < self.noiseGateDB) ? -120 : rawL
                dBR = (rawR < self.noiseGateDB) ? -120 : rawR
            }
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
    
    private static func computeLevelsFallback(from buffer: AVAudioPCMBuffer) -> (Float, Float) {
        let frameCount = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frameCount > 0, channels > 0 else { return (-120, -120) }
        
            // 1) Try Int16 (common for continuity / iPhone-like devices)
        if let int16Data = buffer.int16ChannelData {
            let scale: Float = 1.0 / Float(Int16.max)
            var accL: Float = 0
            var accR: Float = 0
            
            for i in 0..<frameCount {
                let sL = Float(int16Data[0][i]) * scale
                accL += sL * sL
                if channels > 1 {
                    let sR = Float(int16Data[1][i]) * scale
                    accR += sR * sR
                }
            }
            
            let rmsL = sqrtf(accL / Float(frameCount))
            let rmsR = channels > 1 ? sqrtf(accR / Float(frameCount)) : rmsL
            
            let dBL = max(-120.0, min(20 * log10f(max(rmsL, 1e-6)), 0.0))
            let dBR = max(-120.0, min(20 * log10f(max(rmsR, 1e-6)), 0.0))
            return (dBL, dBR)
        }
        
            // 2) Try Int32
        if let int32Data = buffer.int32ChannelData {
            let scale: Float = 1.0 / Float(Int32.max)
            var accL: Float = 0
            var accR: Float = 0
            
            for i in 0..<frameCount {
                let sL = Float(int32Data[0][i]) * scale
                accL += sL * sL
                if channels > 1 {
                    let sR = Float(int32Data[1][i]) * scale
                    accR += sR * sR
                }
            }
            
            let rmsL = sqrtf(accL / Float(frameCount))
            let rmsR = channels > 1 ? sqrtf(accR / Float(frameCount)) : rmsL
            
            let dBL = max(-120.0, min(20 * log10f(max(rmsL, 1e-6)), 0.0))
            let dBR = max(-120.0, min(20 * log10f(max(rmsR, 1e-6)), 0.0))
            return (dBL, dBR)
        }
        
            // 3) Don’t know the sample type → keep silent
        return (-120, -120)
    }
    
    
    private func processLevels(left: Float, right: Float) {
        var l = left
        var r = right
        let originalL = l
        let originalR = r
        let lowerName = selectedDevice.name.lowercased()
        let isDisplayOrUltrafine = lowerName.contains("display") || lowerName.contains("ultrafine")
        let isLGUltraFine = lowerName.contains("lg ultrafine") || lowerName.contains("lg ultrafine display")
        var gatedThisFrame = false
        
            // Force real silence through for display/LG devices
        if isDisplayOrUltrafine && originalL <= -90 && originalR <= -90 {
            smoothedLeft = -120
            smoothedRight = -120
            currentLeftLevel = -120
            currentRightLevel = -120
            leftLevelSubject.send(-120)
            rightLevelSubject.send(-120)
            let stats = AudioStats(left: -120,
                                   right: -120,
                                   inputName: selectedDevice.name,
                                   inputID: Int(selectedDevice.id))
            statsSubject.send(stats)
            lastFrameWasGated = true
            isGatedSubject.send(true)
            return
        }
        
            // Arm/disarm a short "talking" window for display/LG mics.
            // Behavior:
            //  - Any frame above `speechOn` resets the talking window (we're clearly talking).
            //  - As soon as we drop below `speechOn`, we start counting down every frame,
            //    regardless of whether we're in the -40 dB idle shelf. That way, long
            //    stretches of the LG's fake idle floor eventually clamp to silence instead
            //    of looking "hot" forever after you stop talking.
        if isDisplayOrUltrafine {
            let maxLevel = max(originalL, originalR)
            let speechOn: Float = -34
            let talkingWindowFrames = 60  // ~1–1.2s at current tap cadence
            
            if maxLevel > speechOn {
                    // Active speech detected: keep the window open for a bit longer
                displayTalkingFrames = talkingWindowFrames
            } else if displayTalkingFrames > 0 {
                    // Below the speech-on threshold: decay the talking window every frame
                    // so that sustained idle shelves (around -37 to -40 dB) eventually
                    // transition to true "silent" behavior and let the idle clamps engage.
                displayTalkingFrames -= 1
            }
        }
            // If we're on a display/LG mic, not currently in a talking window, and both channels
            // sit well below a "speech-ish" floor, treat this as hard idle and clamp to silence.
            // This keeps the needle pinned down between utterances instead of bouncing on the
            // panel's idle shelf, while still allowing real speech (which rises above this floor)
            // to punch through.
        if isDisplayOrUltrafine && displayTalkingFrames == 0 {
            let speechIdleFloor: Float = -34  // anything quieter than this is treated as non-speech idle
            if originalL <= speechIdleFloor && originalR <= speechIdleFloor {
                l = -120
                r = -120
                gatedThisFrame = true
            }
        }
            // For LG / display mics: if we're NOT in a talking window and the raw value
            // sits in the known “fake idle” band (-70 dB … -33 dB), just publish silence
            // and bail out. This prevents the meter from looking hot at idle while still
            // allowing real speech (which will push levels above this band) to get through.
        if isDisplayOrUltrafine && displayTalkingFrames == 0 {
            let fakeIdleMin: Float = -70   // lower end of the noisy shelf we saw in logs
            let fakeIdleMax: Float = -33   // upper end of the noisy shelf we saw in logs
            let rawInFakeBandL = (originalL >= fakeIdleMin && originalL <= fakeIdleMax)
            let rawInFakeBandR = (originalR >= fakeIdleMin && originalR <= fakeIdleMax)
                // Don’t immediately clamp the very first frames rising out of true silence.
            let wasFullySilent = (smoothedLeft <= -90 && smoothedRight <= -90)
            if (rawInFakeBandL || rawInFakeBandR) && !wasFullySilent {
                gatedThisFrame = true
                smoothedLeft = -120
                smoothedRight = -120
                currentLeftLevel = smoothedLeft
                currentRightLevel = smoothedRight
                leftLevelSubject.send(smoothedLeft)
                rightLevelSubject.send(smoothedRight)
                let stats = AudioStats(left: smoothedLeft,
                                       right: smoothedRight,
                                       inputName: selectedDevice.name,
                                       inputID: Int(selectedDevice.id))
                statsSubject.send(stats)
                lastFrameWasGated = true
                isGatedSubject.send(true)
                return
            }
        }
        
            // Hard idle clamp for LG / display mics: if we're not in a talking window,
            // anything above about -60 dB is just the panel's noisy floor. Treat it as silence
            // so the UI doesn't look "hot" at idle.
        if isDisplayOrUltrafine && displayTalkingFrames == 0 {
            let displayIdleCeiling: Float = -60
            if l > displayIdleCeiling { l = -120; gatedThisFrame = true }
            if r > displayIdleCeiling { r = -120; gatedThisFrame = true }
        }
        
            // ... inside processLevels(...) right after you compute isDisplayOrUltrafine etc.
        
        if isDisplayOrUltrafine {
            let rawDropL = smoothedLeft - originalL
            let rawDropR = smoothedRight - originalR
            let bigDrop: Float = 10.0   // slightly bigger than noise, smaller than your 12 dB one
            
                // Case 1: we were already talking → always ignore the spike
            if displayTalkingFrames > 0 {
                if rawDropL > bigDrop && originalL > -110 {
                    l = smoothedLeft
                    displayTalkingFrames = max(displayTalkingFrames, 10)
                }
                if rawDropR > bigDrop && originalR > -110 {
                    r = smoothedRight
                    displayTalkingFrames = max(displayTalkingFrames, 10)
                }
            } else {
                    // Case 2: we were NOT talking yet, but this looks exactly like the LG “one bad frame”
                    // (we were around -35..-45 and suddenly got a much lower frame)
                let wasInDisplayIdle = (smoothedLeft > -50 && smoothedLeft < -30) || (smoothedRight > -50 && smoothedRight < -30)
                if wasInDisplayIdle {
                    if rawDropL > bigDrop && originalL > -110 {
                        l = smoothedLeft
                    }
                    if rawDropR > bigDrop && originalR > -110 {
                        r = smoothedRight
                    }
                }
            }
        }
        
            // Some display/LG mics report a periodic "low" buffer (-60…-80 dB) even while idle around -40 dB.
            // If we see a sudden large drop compared to our current smoothed value, hold the previous value
            // for a couple of frames so the UI needle doesn't jump backward for no audio reason.
            // Some display/LG mics report a periodic "low" buffer (-60…-80 dB) even while idle around -40 dB.
            // If we see a sudden large drop compared to our current smoothed value, hold the previous value
            // for a couple of frames so the UI needle doesn't jump backward for no audio reason.
            // Extra guard: some LG / display mics report an overly hot idle around -30 dB.
            // If we are NOT currently talking, hard-cap the raw level to something more reasonable
            // so the meter doesn't look "hot" at idle.
        if isDisplayOrUltrafine && displayTalkingFrames == 0 {
            let maxIdleDisplayDB: Float = -42
            if l > maxIdleDisplayDB { l = maxIdleDisplayDB; gatedThisFrame = true }
            if r > maxIdleDisplayDB { r = maxIdleDisplayDB; gatedThisFrame = true }
        }
        
        if isDisplayOrUltrafine && displayTalkingFrames == 0 {
            let dropL = smoothedLeft - l
            let dropR = smoothedRight - r
            let largeDropThreshold: Float = 10.0
                // The problematic LG frame sometimes lands a bit lower than -70, so widen the idle window.
            let landedInIdleL = (l <= -33 && l >= -80)
            let landedInIdleR = (r <= -33 && r >= -80)
            var held = false
            if dropL > largeDropThreshold && landedInIdleL && displayPulseHoldFrames < displayPulseHoldMax {
                l = smoothedLeft
                held = true
            }
            if dropR > largeDropThreshold && landedInIdleR && displayPulseHoldFrames < displayPulseHoldMax {
                r = smoothedRight
                held = true
            }
            if held {
                displayPulseHoldFrames += 1
            } else {
                displayPulseHoldFrames = 0
            }
        }
        
            // LG / display mics often idle around -40 dB with no real audio.
            // If the incoming level sits in that band and isn’t actually rising,
            // clamp it to silence so the UI doesn’t look “hot” at idle.
        if isDisplayOrUltrafine && displayTalkingFrames == 0 {
            let idleMin: Float = -60
            let idleMax: Float = -33
            let isInIdleBandL = (l >= idleMin && l <= idleMax)
            let isInIdleBandR = (r >= idleMin && r <= idleMax)
                // only treat the display’s idle shelf as "fake" if we were already truly quiet
            let wasQuietL = smoothedLeft < -65
            let wasQuietR = smoothedRight < -65
            if isInIdleBandL && wasQuietL {
                l = -120
                gatedThisFrame = true
            }
            if isInIdleBandR && wasQuietR {
                r = -120
                gatedThisFrame = true
            }
        }
        
            // For LG UltraFine mics we want to go through the same display/ultrafine path
            // instead of publishing raw levels and returning early. We only do a tiny
            // stabilization for the first few frames after an engine start.
        if isLGUltraFine && framesSinceEngineStart < 3 {
                // lightly smooth just the first frames to avoid the backward jump
            smoothedLeft = smoothing * l + (1 - smoothing) * smoothedLeft
            smoothedRight = smoothing * r + (1 - smoothing) * smoothedRight
            currentLeftLevel = smoothedLeft
            currentRightLevel = smoothedRight
            leftLevelSubject.send(smoothedLeft)
            rightLevelSubject.send(smoothedRight)
            let stats = AudioStats(left: smoothedLeft,
                                   right: smoothedRight,
                                   inputName: selectedDevice.name,
                                   inputID: Int(selectedDevice.id))
            statsSubject.send(stats)
            lastFrameWasGated = gatedThisFrame
            framesSinceEngineStart += 1
            return
        }
        
            // Devices like displays, iPhones, and Lumina cameras often sit at a fixed dB.
            // If we run adaptive floor on them, we “learn” that idle and clamp to silence.
        let isLuminaLike = lowerName.contains("lumina") || lowerName.contains("camera")
        let isContinuityIPhone = lowerName.contains("iphone")
        var skipAdaptiveNoiseFloor =
        lowerName.contains("iphone") ||
        lowerName.contains("ak4571") ||
        lowerName.contains("microphone")
            // LG / display mics sit on a fixed noisy floor; don’t let adaptive learning immediately clamp them.
        if isDisplayOrUltrafine {
            skipAdaptiveNoiseFloor = true
        }
        
        let now = Date()
        let canLearnNow = (noiseFloorLearnNotBefore == nil) || (now >= noiseFloorLearnNotBefore!)
        
        if !skipAdaptiveNoiseFloor && canLearnNow {
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
        
            // Update display/Ultrafine cooldown each frame
        if displayActivityCooldown > 0 {
            displayActivityCooldown -= 1
        }
        
            // Special-case display / UltraFine mics: only clamp the learned idle band when we're NOT already seeing
            // real upward motion or clearly-above-idle audio. This prevents the needle from jumping backward when the
            // device reports a steady idle but the user actually starts talking.
        if isDisplayOrUltrafine,
           learnedNoiseFloorSamples >= noiseFloorLearnWindow,
           displayActivityCooldown == 0 {
            if displayTalkingFrames == 0 {
                let band: Float = 3.5  // dB around the learned idle
                let isRisingL = originalL > smoothedLeft
                let isRisingR = originalR > smoothedRight
                let isClearlyAboveIdleL = originalL > learnedNoiseFloor + band
                let isClearlyAboveIdleR = originalR > learnedNoiseFloor + band
                
                if l > learnedNoiseFloor - band && l < learnedNoiseFloor + band && !isRisingL && !isClearlyAboveIdleL {
                    l = -120
                    gatedThisFrame = true
                }
                if r > learnedNoiseFloor - band && r < learnedNoiseFloor + band && !isRisingR && !isClearlyAboveIdleR {
                    r = -120
                    gatedThisFrame = true
                }
            }
        }
        
            // Stronger, signal-aware gate for display/Ultrafine mics
        let inDisplayCooldown = displayActivityCooldown > 0
        if lowerName.contains("display") || lowerName.contains("ultrafine") {
            if displayTalkingFrames > 0 {
                    // while speech is active, only block obvious single-frame dips
                let spikeDropL = smoothedLeft - l
                let spikeDropR = smoothedRight - r
                if spikeDropL > 6 { l = smoothedLeft }
                if spikeDropR > 6 { r = smoothedRight }
            }
            let isStrongL = l > -30
            let isStrongR = r > -30
            let isTransientL = abs(l - smoothedLeft) > 6
            let isTransientR = abs(r - smoothedRight) > 6
                // If we have obviously loud speech, don't let later gating push it back down.
            let clearlyLoud = isStrongL || isStrongR
                // Detect speech that is modestly above the learned idle floor
            let isAboveIdleL = originalL > learnedNoiseFloor + 4
            let isAboveIdleR = originalR > learnedNoiseFloor + 4
            
                // 1) gate out the flat idle band
                // allow forward motion (rising level) to break out of the idle clamp so the needle doesn't jump backward
            let isRisingL = originalL > smoothedLeft
            let isRisingR = originalR > smoothedRight
            
                // Arm cooldown immediately if we see real activity
            if isStrongL || isStrongR || isTransientL || isTransientR || isRisingL || isRisingR {
                displayActivityCooldown = max(displayActivityCooldown, 12)
            }
            
            if !inDisplayCooldown && !isLGUltraFine {
                if displayTalkingFrames == 0 {
                    if !clearlyLoud {
                        if !isStrongL && !isTransientL && !isRisingL && !isAboveIdleL {
                            l = -120
                            gatedThisFrame = true
                        }
                        if !isStrongR && !isTransientR && !isRisingR && !isAboveIdleR {
                            r = -120
                            gatedThisFrame = true
                        }
                    }
                }
            }
            
                // 2) even when we pass through, cap how fast the needle can move on these mics
                //    to stop the wild bounce caused by HAL/device reporting jittery RMS values.
            let maxStepPerFrame: Float = 8.0 // dB
            if l > -120 {
                let deltaL = l - smoothedLeft
                if abs(deltaL) > maxStepPerFrame {
                    l = smoothedLeft + (deltaL > 0 ? maxStepPerFrame : -maxStepPerFrame)
                }
            }
            if r > -120 {
                let deltaR = r - smoothedRight
                if abs(deltaR) > maxStepPerFrame {
                    r = smoothedRight + (deltaR > 0 ? maxStepPerFrame : -maxStepPerFrame)
                }
            }
        }
        
            // Lumina / camera-like devices sometimes sit at a fixed mid band ("hot but not responsive").
            // If we see a level in that band that barely moves, treat it as idle and clamp to silence so UI can recover.
        if isLuminaLike {
                // Lumina raw feed tends to hover between -65 and -48 even when "quiet".
                // Treat that whole mid band as idle unless it's clearly above -40 (i.e. real signal).
            if l > -70 && l < -40 {
                l = -120
            }
            if r > -70 && r < -40 {
                r = -120
            }
        } else if isContinuityIPhone {
            let stuckBandMin: Float = -60
            let stuckBandMax: Float = -40
            let smallDelta: Float = 1.0
            if l > stuckBandMin && l < stuckBandMax && abs(l - smoothedLeft) < smallDelta {
                l = max(l, -90)
            }
            if r > stuckBandMin && r < stuckBandMax && abs(r - smoothedRight) < smallDelta {
                r = max(r, -90)
            }
        }
            // (removed hard clamp for display/UltraFine mics; now handled by adaptive noise floor logic)
        
            // existing smoothing logic stays the same
            // device-aware smoothing: some devices (AK4571, Lumina/camera) look "stuck" with heavy smoothing
            // device-aware smoothing: some devices (AK4571, Lumina/camera) need special handling
        let name = lowerName
        let isLuminaOrCamera = name.contains("lumina") || name.contains("camera")
        
        if isLuminaOrCamera {
                // asymmetric smoothing: fast up, slow down
            let riseSmoothing: Float = 0.35
            let fallSmoothing: Float = 0.12
                // left
            if l > smoothedLeft {
                smoothedLeft = riseSmoothing * l + (1 - riseSmoothing) * smoothedLeft
            } else {
                smoothedLeft = fallSmoothing * l + (1 - fallSmoothing) * smoothedLeft
            }
                // right
            if r > smoothedRight {
                smoothedRight = riseSmoothing * r + (1 - riseSmoothing) * smoothedRight
            } else {
                smoothedRight = fallSmoothing * r + (1 - fallSmoothing) * smoothedRight
            }
        } else if name.contains("ak4571") || name.contains("iphone") || name.contains("microphone") {
            smoothedLeft = l
            smoothedRight = r
        } else if name.contains("display") || name.contains("ultrafine") {
                // display / LG mics: fast rise, much faster fall so the meter doesn't stick
            let rise: Float = 0.45
            let fall: Float = 0.70   // was 0.40 — bigger fall makes the needle relax quicker
            if l > smoothedLeft {
                smoothedLeft = rise * l + (1 - rise) * smoothedLeft
            } else {
                smoothedLeft = fall * l + (1 - fall) * smoothedLeft
            }
            if r > smoothedRight {
                smoothedRight = rise * r + (1 - rise) * smoothedRight
            } else {
                smoothedRight = fall * r + (1 - fall) * smoothedRight
            }
        } else {
            smoothedLeft  = smoothing * l  + (1 - smoothing) * smoothedLeft
            smoothedRight = smoothing * r  + (1 - smoothing) * smoothedRight
        }
        
        currentLeftLevel = smoothedLeft
        currentRightLevel = smoothedRight
        leftLevelSubject.send(smoothedLeft)
        rightLevelSubject.send(smoothedRight)
        
        let stats = AudioStats(left: smoothedLeft,
                               right: smoothedRight,
                               inputName: selectedDevice.name,
                               inputID: Int(selectedDevice.id))
        statsSubject.send(stats)
        lastFrameWasGated = gatedThisFrame
        isGatedSubject.send(gatedThisFrame)
        
            // Arm displayActivityCooldown only on real motion or moderately loud audio for display/UltraFine mics
        if lowerName.contains("display") || lowerName.contains("ultrafine") {
            let burstL = l > smoothedLeft + 2.5
            let burstR = r > smoothedRight + 2.5
            let loudL = l > -45
            let loudR = r > -45
            if burstL || burstR || loudL || loudR {
                displayActivityCooldown = max(displayActivityCooldown, 6)
            }
        }
        
            // Device-aware silence watchdog: iPhone/Continuity tends to come up silent, so retry sooner.
            // Lumina/camera-like devices can show a constant floor, so don't hammer the tap for them.
        let watchSilence = !(isLuminaLike || isContinuityIPhone || isDisplayOrUltrafine)
        if l <= -119 && r <= -119 {
            if watchSilence {
                silentCount += 1
                let maxSilentFrames = isContinuityIPhone ? 6 : 20
                if silentCount == maxSilentFrames {
                    logger.warning("🛑 Silent input detected (\(lowerName)).")
                    scheduleTapRetry(reason: "\(lowerName) sustained silence")
                }
            }
        } else {
            silentCount = 0
            tapRetryCount = 0
            pendingTapRetry?.cancel(); pendingTapRetry = nil
        }
        framesSinceEngineStart += 1
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
                
                
                
                self.inputAutoSelectGraceUntil = Date().addingTimeInterval(1.0)
                    // Restart engine permission‑aware to retarget input node and reinstall the tap
                self.pendingTapRetry?.cancel(); self.pendingTapRetry = nil
                self.tapRetryCount = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    guard let self = self else { return }
                    self.verifyMicPermissionThen { [weak self] in
                        guard let self = self else { return }
                        if self.engine.isRunning { self.engine.stop() }
                        if self.tapInstalled {
                            self.engine.inputNode.removeTap(onBus: 0)
                            self.tapInstalled = false
                        }
                        if !self.isStarting { self.startEngine() }
                    }
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

