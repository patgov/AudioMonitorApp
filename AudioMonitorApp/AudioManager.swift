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
    
    struct DeviceCapabilities {
        let name: String
        let inputID: Int
        let channelCount: Int
        let sampleRate: Double
        let isValidInput: Bool
    }
    
    struct ActiveInputInfo {
        let selectedName: String
        let selectedID: Int
        let reportedName: String
        let reportedID: Int
        
        var isMatching: Bool {
            selectedID == reportedID && !selectedName.isEmpty && !reportedName.isEmpty
        }
    }
    
        // Exposed device capability and active-input info streams
    private let deviceCapabilitiesSubject = CurrentValueSubject<DeviceCapabilities?, Never>(nil)
    var deviceCapabilitiesStream: AnyPublisher<DeviceCapabilities?, Never> { deviceCapabilitiesSubject.eraseToAnyPublisher() }
    
    private let activeInputSubject = CurrentValueSubject<ActiveInputInfo?, Never>(nil)
    var activeInputStream: AnyPublisher<ActiveInputInfo?, Never> { activeInputSubject.eraseToAnyPublisher() }
    
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
        // ... existing engine state properties ...
    private var framesSinceEngineStart: Int = 0
    private var hasSeenNonSilentFrameForCurrentEngine = false
    private var didAttemptBluetoothFallbackForCurrentEngine = false
    
    private var engineStartedAt: Date?
    private let bluetoothSilenceFallbackSeconds: TimeInterval = 1.5
    
        // Tracks whether the user has explicitly chosen a device in-app
    private var userPinnedSelection: Bool = false
    
        // Tracks if last frame was gated (for UI/diagnostics)
    private var lastFrameWasGated: Bool = false
    
        // Wait before learning noise floor after a route/device change
    private var noiseFloorLearnNotBefore: Date? = nil
    
        // Track sustained quiet for display/LG mics so we can clamp real silence
    private var displayQuietFrames: Int = 0
    private let displayQuietFramesForSilence: Int = 8   // ~120–180ms of quiet before hard-clamp
    
        // Signal health tracking (used to warn when we see essentially no usable audio)
    private var framesObserved: Int = 0
    private var maxLevelObserved: Float = -120.0
        // Flat-level watchdog: detects when we see a low, nearly-constant level for a long time ("zombie" paths)
    private var flatLevelFrameCount: Int = 0
    private var flatLevelLastValue: Float = -120.0
    private let flatLevelTolerance: Float = 0.4        // dB window within which we treat frames as "flat"
    private let flatLevelFrameThreshold: Int = 90      // frames of flat, low-level audio before we retry the tap
    let signalWarningSubject = CurrentValueSubject<String?, Never>(nil)
    public var signalWarningStream: AnyPublisher<String?, Never> { signalWarningSubject.eraseToAnyPublisher() }
    
        // Dead-silence detector (for devices that return hard zero like some display mics)
    private var deadSilenceFrameCount: Int = 0
    private let deadSilenceFrameThreshold: Int = 60   // number of consecutive full-silence frames before auto-restart
    private var lastSilenceRecoveryAt: Date? = nil
    private let silenceRecoveryMinInterval: TimeInterval = 3.0  // seconds between auto-recovery attempts
    
    
    
    
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
        //#if os(macOS)
        //#if os(macOS)
#if os(macOS)
        /// Force the macOS System Settings default input to follow the current in-app selection.
    private var forceSystemDefaultToSelected = false
        /// Tracks whether we've registered a listener for default input changes.
    private var defaultListenerInstalled = false
        /// Prevent recursive/default-switch feedback loops
    private var isSwitchingDefaultInput = false
    private var pendingSystemDefaultInput: InputAudioDevice? = nil
    private var lastSystemInputChangeAt: Date? = nil
    private let bluetoothAdoptionDelay: TimeInterval = 1.5
    private let bluetoothAdoptionTimeout: TimeInterval = 5.0
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
    
    
    
    private func resetSignalHealth() {
        framesObserved = 0
        maxLevelObserved = -120.0
        flatLevelFrameCount = 0
        flatLevelLastValue = -120.0
        signalWarningSubject.send(nil)
    }
    
        /// Auto-recovery path when we see sustained full-scale digital silence from the current input.
        /// This is primarily to handle display / LG mics that occasionally fall into a "zombie" state
        /// where CoreAudio returns zeros with a valid format and device ID.
    private func attemptSilenceRecoveryIfNeeded() {
        let now = Date()
        if let last = lastSilenceRecoveryAt, now.timeIntervalSince(last) < silenceRecoveryMinInterval {
            return
        }
        lastSilenceRecoveryAt = now
        
        logger.warning("🩺 Sustained digital silence detected from \(self.selectedDevice.name) — restarting engine and refreshing devices (auto-recover)")
        
            // Reset health counters
        framesObserved = 0
        maxLevelObserved = -120.0
        flatLevelFrameCount = 0
        flatLevelLastValue = -120.0
        silentCount = 0
        deadSilenceFrameCount = 0
        hasSeenNonSilentFrameForCurrentEngine = false
        didAttemptBluetoothFallbackForCurrentEngine = false
        
            // Cancel any pending tap retries
        pendingTapRetry?.cancel()
        pendingTapRetry = nil
        tapRetryCount = 0
        
            // Tear down current tap and engine
        if engine.isRunning {
            engine.stop()
        }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        
#if os(macOS)
            // Refresh device list in case the underlying HAL device changed or disappeared
        refreshInputDevices()
#endif
        
            // Restart the engine on the (possibly updated) selected device
        if !isStarting {
            startEngine()
        }
    }
    
        // MARK: - Selected Device
    public private(set) var selectedDevice: InputAudioDevice = .none
    
        // MARK: - Public Controls
    public func selectDevice(_ device: InputAudioDevice) {
        DispatchQueue.main.async {
                // Ignore if selecting the same device
            if device.id == self.selectedDevice.id { return }
            
                // Mark that the user has explicitly chosen a device in-app
            self.userPinnedSelection = true
            
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
            
                // Reset signal-health tracking for the new device
            self.resetSignalHealth()
                // New engine instance: we haven't seen any real samples yet.
            self.hasSeenNonSilentFrameForCurrentEngine = false
            self.didAttemptBluetoothFallbackForCurrentEngine = false
            
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
        
#if os(macOS)
            // If HAL has recently thrown -10877 (or similar) during device queries,
            // give it a short window to recover before rebuilding the engine graph.
        if let backoff = halBackoffUntil, backoff > Date() {
            logger.warning("⏸️ HAL backoff active until \(backoff) — skipping startEngine()")
            return
        }
#endif
        
        isStarting = true
        defer { isStarting = false }
        
            // Tear down any previous tap/graph safely
        if engine.isRunning { engine.stop() }
        
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
            
                // Publish current device capabilities based on the running engine input
            let caps = DeviceCapabilities(
                name: self.selectedDevice.name,
                inputID: Int(self.selectedDevice.id),
                channelCount: Int(fmt.channelCount),
                sampleRate: fmt.sampleRate,
                isValidInput: fmt.channelCount > 0
            )
            self.deviceCapabilitiesSubject.send(caps)
            
                // Publish basic active-input info (reported device is the current selection for now)
            let active = ActiveInputInfo(
                selectedName: self.selectedDevice.name,
                selectedID: Int(self.selectedDevice.id),
                reportedName: self.selectedDevice.name,
                reportedID: Int(self.selectedDevice.id)
            )
            self.activeInputSubject.send(active)
            
                // reset meter only after we actually have a running engine on the new device
            self.smoothedLeft = -80
            self.smoothedRight = -80
            self.currentLeftLevel = -80
            self.currentRightLevel = -80
            self.leftLevelSubject.send(-80)
            self.rightLevelSubject.send(-80)
            self.framesSinceEngineStart = 0
            
                // reset signal-health tracking for the newly started engine
            self.resetSignalHealth()
                // New engine instance: no real samples or Bluetooth fallback yet
            self.hasSeenNonSilentFrameForCurrentEngine = false
            self.didAttemptBluetoothFallbackForCurrentEngine = false
            self.engineStartedAt = Date()
            
            
        } catch {
            logger.error("❌ Engine failed to start: \(error.localizedDescription)")
            
#if os(macOS)
                // Treat any start failure as a HAL stress signal and back off briefly,
                // so we don't keep rebuilding the graph into a failing HAL.
            halBackoffUntil = Date().addingTimeInterval(1.5)
            logger.warning("⏸️ Entering HAL backoff for 1.5s due to engine start failure")
#endif
            
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
            // Suppress restarts while we're inside the system-driven input grace window
        if let grace = inputAutoSelectGraceUntil, grace > Date() {
            logger.warning("⏳ scheduleEngineRestart suppressed during system input grace window – \(reason)")
            return
        }
            // Suppress restarts while a deferred Bluetooth default is pending adoption
        if pendingSystemDefaultInput != nil {
            logger.warning("⏳ scheduleEngineRestart suppressed while pending Bluetooth default exists – \(reason)")
            return
        }
        
        guard engineRestartRetryCount < engineRestartRetryMax else {
            logger.error("🛑 Engine restart retry limit reached — giving up")
            return
        }
        engineRestartRetryCount += 1
        
        let baseDelay = delay ?? engineRestartRetryDelay
        var effectiveDelay = baseDelay
        
            // If HAL is in a backoff window, push the restart to just after that window
        if let backoff = halBackoffUntil {
            let remaining = backoff.timeIntervalSince(Date())
            if remaining > 0 {
                effectiveDelay = max(baseDelay, remaining + 0.1)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + effectiveDelay) { [weak self] in
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
            lowerName.contains("microphone") ||
            lowerName.contains("airpods") ||
            lowerName.contains("beats") ||
            lowerName.contains("usb") ||
            lowerName.contains("interface") ||
            lowerName.contains("display") ||
            lowerName.contains("ultrafine")
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
            lowerName.contains("microphone") ||
            lowerName.contains("airpods") ||
            lowerName.contains("beats") ||
            lowerName.contains("usb") ||
            lowerName.contains("interface") ||
            lowerName.contains("display") ||
            lowerName.contains("ultrafine")
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
            /// For now, treat display / LG mics like “real” mics (Beats, AK4571, etc.) for metering.
        let treatDisplayLikeRealMic = isDisplayOrUltrafine
        var gatedThisFrame = false
        let isAirPods = lowerName.contains("airpods")
        let isBeats = lowerName.contains("beats")
        let isBluetoothHeadset = isAirPods || isBeats
        let isContinuityIPhone = lowerName.contains("iphone")
        
            // Track whether we've ever seen a non-silent frame on this engine instance.
            // Use the original (pre-gated) levels so display/Ultrafine clamping doesn't hide real samples.
        let rawMax = max(originalL, originalR)
        let isFrameSilent = (rawMax <= -119)
        if !isFrameSilent {
            hasSeenNonSilentFrameForCurrentEngine = true
        }
        
            // For Bluetooth headsets, while the new engine instance is still fully silent,
            // hold the UI at hard silence instead of reusing the last device's level.
            // This avoids the “levels lost” freeze while macOS brings the SCO/HFP path online.
        let bluetoothPreRollGateDB: Float = -80.0
        let isBluetoothPreRoll = isBluetoothHeadset &&
        !hasSeenNonSilentFrameForCurrentEngine &&
        rawMax < bluetoothPreRollGateDB
        if isBluetoothPreRoll {
            l = -120
            r = -120
        }
        
            // --- Display / LG UltraFine: speech-armed hard gate (disabled when treating as real mic) --- //
        if isDisplayOrUltrafine && !treatDisplayLikeRealMic {
            let maxLevel = max(originalL, originalR)
            let smoothedMax = max(smoothedLeft, smoothedRight)
            
                // Decay the talking window if it's currently active
            if displayTalkingFrames > 0 {
                displayTalkingFrames -= 1
            }
            
                // Only arm "talking" when we see a clearly speech-like transient:
                //  - level is loud-ish (>-30 dBFS), and
                //  - we see a sudden upward jump compared to the current smoothed value.
            let armThreshold: Float = -30.0
            let armDelta: Float = 8.0
            let delta = maxLevel - smoothedMax
            
            if delta > armDelta && maxLevel > armThreshold {
                    // Real speech detected: keep the gate open for a short window
                displayTalkingFrames = 40   // ~600–800 ms depending on tap cadence
            }
                // (Removed forced silence when not in a talking window)
        }
        
            // ... inside processLevels(...) right after you compute isDisplayOrUltrafine etc.
        
            // --- Display / LG UltraFine: speech-armed hard gate (disabled when treating as real mic) --- //
            // if isDisplayOrUltrafine && !treatDisplayLikeRealMic {
            //            let rawDropL = smoothedLeft - originalL
            //            let rawDropR = smoothedRight - originalR
            //            let bigDrop: Float = 10.0
            //            let isVeryQuietL = originalL < -55    // treat deep drops as real silence, not glitches
            //            let isVeryQuietR = originalR < -55
            //
            //            if displayTalkingFrames > 0 {
            //                if rawDropL > bigDrop && originalL > -110 && !isVeryQuietL {
            //                    l = smoothedLeft
            //                    displayTalkingFrames = max(displayTalkingFrames, 10)
            //                }
            //                if rawDropR > bigDrop && originalR > -110 && !isVeryQuietR {
            //                    r = smoothedRight
            //                    displayTalkingFrames = max(displayTalkingFrames, 10)
            //                }
        
        if isDisplayOrUltrafine && !treatDisplayLikeRealMic && displayTalkingFrames == 0 {
            let maxIdleDisplayDB: Float = -42
            if l > maxIdleDisplayDB { l = maxIdleDisplayDB; gatedThisFrame = true }
            if r > maxIdleDisplayDB { r = maxIdleDisplayDB; gatedThisFrame = true }
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
        if isDisplayOrUltrafine && !treatDisplayLikeRealMic && displayTalkingFrames == 0 {
            let maxIdleDisplayDB: Float = -42
            if l > maxIdleDisplayDB { l = maxIdleDisplayDB; gatedThisFrame = true }
            if r > maxIdleDisplayDB { r = maxIdleDisplayDB; gatedThisFrame = true }
        }
        
        if isDisplayOrUltrafine && !treatDisplayLikeRealMic && displayTalkingFrames == 0 {
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
        if isDisplayOrUltrafine && !treatDisplayLikeRealMic && displayTalkingFrames == 0 {
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
        if isLGUltraFine && !treatDisplayLikeRealMic && framesSinceEngineStart < 3 {
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
            //    let isContinuityIPhone = lowerName.contains("iphone")
            // Only skip adaptive noise-floor learning for devices that are known to have odd, fixed floors
            // or are handled by dedicated logic elsewhere (display mics, Lumina/camera, Continuity iPhone,
            // Beats/AirPods, and common USB/interface-style inputs).
        let isUSBOrInterface = lowerName.contains("usb") || lowerName.contains("interface")
        let skipAdaptiveNoiseFloor =
        isContinuityIPhone ||
        isLuminaLike ||
        isDisplayOrUltrafine ||
        isAirPods ||
        isBeats ||
        isUSBOrInterface
        
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
        if isDisplayOrUltrafine && !treatDisplayLikeRealMic,
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
        if (lowerName.contains("display") || lowerName.contains("ultrafine")) && !treatDisplayLikeRealMic {
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
        if isContinuityIPhone {
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
        } else if name.contains("ak4571") ||
                    name.contains("iphone") ||
                    name.contains("microphone") ||
                    name.contains("airpods") ||
                    name.contains("beats") ||
                    name.contains("usb") ||
                    name.contains("interface") ||
                    name.contains("display") ||
                    name.contains("ultrafine") {
                // “Real” mic / interface path: minimal smoothing so the meter tracks the signal closely.
            smoothedLeft = l
            smoothedRight = r
        } else if (name.contains("display") || name.contains("ultrafine")) && !treatDisplayLikeRealMic {
                // (currently disabled by treatDisplayLikeRealMic) – legacy display-specific smoothing kept for future tuning.
            let rise: Float = 0.45
            let fall: Float = 0.70
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
        
            // --- Signal health tracking ---
            // Track how many frames we have seen and the maximum level so far; if we never
            // see anything above a very low threshold after a short window, emit a warning
        let levelForHealth = max(smoothedLeft, smoothedRight)
        framesObserved += 1
        maxLevelObserved = max(maxLevelObserved, levelForHealth)
        let framesBeforeCheck = 50  // tune based on tap cadence (~0.5s worth of frames)
        if framesObserved == framesBeforeCheck {
                // For Bluetooth headsets, the OS can legitimately be silent for a few seconds
                // while the SCO/HFP path comes online. Don't treat that initial window as failure
                // until we've actually seen at least one non-silent frame.
            if isBluetoothHeadset && !hasSeenNonSilentFrameForCurrentEngine {
                    // Skip health-based retries for the initial bring-up silence on Bluetooth.
            } else {
                if maxLevelObserved < -80 {
                    let warning = "Very low signal from \(selectedDevice.name). Check mic selection, gain, or distance."
                    signalWarningSubject.send(warning)
                    if engine.isRunning {
                        self.scheduleTapRetry(reason: "very low signal after device change")
                    }
                } else {
                    signalWarningSubject.send(nil)
                }
            }
        }
            // Flat, low-level watchdog: some devices can fall into a "zombie" state where they
            // report a constant, very low-level noise floor without carrying real signal. Detect
            // this by watching for many consecutive frames where the level barely changes.
        let watchFlatLevels = !(isContinuityIPhone || isDisplayOrUltrafine || (isBluetoothHeadset && !hasSeenNonSilentFrameForCurrentEngine))
        if watchFlatLevels {
            let curLevel = levelForHealth
            if abs(curLevel - flatLevelLastValue) < flatLevelTolerance {
                flatLevelFrameCount += 1
            } else {
                flatLevelFrameCount = 0
            }
            flatLevelLastValue = curLevel
                // Only treat this as a failure if the flat signal is well below any reasonable speech level.
            if flatLevelFrameCount >= flatLevelFrameThreshold && curLevel < -60 {
                logger.warning("🩺 Flat, low-level signal detected from \(self.selectedDevice.name) – reinstalling tap")
                flatLevelFrameCount = 0
                if engine.isRunning {
                    self.scheduleTapRetry(reason: "flat low-level signal (possible stuck path)")
                }
            }
        } else {
                // For devices we explicitly handle elsewhere (Lumina/camera, Continuity iPhone,
                // AirPods, display mics), don't accumulate flat-level state.
            flatLevelFrameCount = 0
            flatLevelLastValue = levelForHealth
        }
        
            // Arm displayActivityCooldown only on real motion or moderately loud audio for display/UltraFine mics
        if (lowerName.contains("display") || lowerName.contains("ultrafine")) && !treatDisplayLikeRealMic {
            let burstL = l > smoothedLeft + 2.5
            let burstR = r > smoothedRight + 2.5
            let loudL = l > -45
            let loudR = r > -45
            if burstL || burstR || loudL || loudR {
                displayActivityCooldown = max(displayActivityCooldown, 6)
            }
        }
        
            // Device-aware silence watchdog: iPhone/Continuity tends to come up silent, so retry sooner.
            // For silence recovery, we still want to auto-heal Lumina / camera and display / LG paths.
            // For Bluetooth headsets (AirPods / Beats), *only* enable silence-based auto-healing
            // after we've actually seen at least one non-silent frame on the current engine.
            // That way we ignore the initial HFP/SCO bring-up silence, but still heal "zombie" paths later.
        var watchSilence = !(isContinuityIPhone || isDisplayOrUltrafine)
        
        if isBluetoothHeadset && !hasSeenNonSilentFrameForCurrentEngine {
                // Still in the initial bring-up window: ignore silence for generic tap retries,
                // but we may still decide to fall back if the engine stays digitally silent.
            watchSilence = false
        }
        
            // Use the original (pre-gated) levels for detecting true digital silence
        let rawSilent = (originalL <= -119 && originalR <= -119)
        
        if rawSilent {
            if watchSilence {
                silentCount += 1
                let maxSilentFrames = isContinuityIPhone ? 6 : 20
                if silentCount == maxSilentFrames {
                    logger.warning("🛑 Silent input detected (\(lowerName)).")
                    scheduleTapRetry(reason: "\(lowerName) sustained silence")
                }
                    // Global dead-silence detector: for "real" inputs (built-in, interfaces, etc.) we want to
                    // auto-recover if we see sustained digital silence that likely indicates a stuck HAL path.
                deadSilenceFrameCount += 1
                if deadSilenceFrameCount >= deadSilenceFrameThreshold {
                    attemptSilenceRecoveryIfNeeded()
                }
            }
            
                // Special-case Bluetooth: if the engine has been running for a while and we've *never*
                // seen a non-silent frame, treat this as a stuck path and fall back to a non-Bluetooth input.
            if (isBluetoothHeadset || isContinuityIPhone),
               !hasSeenNonSilentFrameForCurrentEngine,
               !didAttemptBluetoothFallbackForCurrentEngine {
                
                let elapsed: TimeInterval
                if let startedAt = engineStartedAt {
                    elapsed = Date().timeIntervalSince(startedAt)
                } else {
                    elapsed = 0
                }
                
                    // Fallback after a short real-time window of pure digital silence
                if elapsed >= bluetoothSilenceFallbackSeconds {
                    didAttemptBluetoothFallbackForCurrentEngine = true
                    logger.warning("🎧 Input \(self.selectedDevice.name) remained fully silent for \(self.framesSinceEngineStart) frames (~\(String(format: "%.2f", elapsed))s) — attempting fallback")
                    fallbackFromBluetoothSilence()
                }
            }
        } else {
            silentCount = 0
            deadSilenceFrameCount = 0
            tapRetryCount = 0
            pendingTapRetry?.cancel(); pendingTapRetry = nil
        }
        
        framesSinceEngineStart += 1
    }
    
    
    private func fallbackFromBluetoothSilence() {
        let lowerName = selectedDevice.name.lowercased()
        let isAirPods = lowerName.contains("airpods")
        let isBeats = lowerName.contains("beats")
        let isBluetoothHeadset = isAirPods || isBeats
        let isContinuityIPhone = lowerName.contains("iphone")
            // We allow this fallback for both Bluetooth headsets and Continuity-style iPhone mics
        guard isBluetoothHeadset || isContinuityIPhone else { return }
        
#if os(macOS)
            // Try to find a reasonable non-Bluetooth, non-display, non-continuity input to fall back to.
            // Prefer "real" mics/interfaces (USB, AK4571, built-in) over iPhone/camera-style devices.
        let devices = inputDevices
        
        let primaryCandidates = devices.filter { dev in
            let n = dev.name.lowercased()
            let isBT = n.contains("airpods") || n.contains("beats")
            let isDisplay = n.contains("display") || n.contains("ultrafine")
            let isContinuity = n.contains("iphone") || n.contains("camera") || n.contains("lumina")
            return !isBT && !isDisplay && !isContinuity
        }
        
        let secondaryCandidates = devices.filter { dev in
            let n = dev.name.lowercased()
            let isBT = n.contains("airpods") || n.contains("beats")
            let isDisplay = n.contains("display") || n.contains("ultrafine")
            return !isBT && !isDisplay
        }
        
        guard let fallback = primaryCandidates.first ?? secondaryCandidates.first else {
            logger.warning("🎧 Wanted to fall back from \(self.selectedDevice.name) but no suitable non‑Bluetooth device was found")
            return
        }
        
        logger.info("🎧 Falling back from input \(self.selectedDevice.name) to \(fallback.name) due to sustained digital silence")
            // Mark this as an explicit user-like choice so we stop auto-following system default
        self.userPinnedSelection = true
        self.selectDevice(fallback)
#endif
    }
    
    
        // MARK: - Device Enumeration & Publishing (moved to class scope)
    private func refreshInputDevices() {
#if os(macOS)
            // If we don’t have TCC approval yet, don’t enumerate or mutate selection
        guard hasMicPermission else {
            logger.warning("🔒 Mic permission not granted — skipping device refresh")
            return
        }
        
            // If HAL just reported a device-level error (e.g. -10877), temporarily
            // back off from further enumeration so the plugin can recover.
        if let backoff = halBackoffUntil, backoff > Date() {
            logger.warning("⏸️ HAL backoff active until \(backoff) — skipping device refresh")
            return
        }
        
        let devices = enumerateInputDevices()
        inputDevicesSubject.send(devices)
        processPendingSystemDefaultIfNeeded(devices: devices)
        if let grace = inputAutoSelectGraceUntil, grace > Date() {
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
                    self.userPinnedSelection = false
                    logger.info("🎯 Using system default input for UI: \(def.name) [id: \(def.id)]")
                } else if let first = devices.first {
                    self.selectedDevice = first
                    self.selectedInputDeviceSubject.send(first)
                    self.userPinnedSelection = false
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
                    self.userPinnedSelection = false
                    logger.info("🎯 Adopted system default (replacement): \(def.name) [id: \(def.id)]")
                } else if let first = devices.first {
                    self.selectedDevice = first
                    self.selectedInputDeviceSubject.send(first)
                    self.userPinnedSelection = false
                    logger.info("🎯 Adopted first device (replacement): \(first.name) [id: \(first.id)]")
                } else {
                    logger.error("❌ No valid input device found for selection.")
                }
            }
        }
#else
            // Non-macOS: optionally populate via AVAudioSession.availableInputs
        inputDevicesSubject.send([])
#endif
    }
    
        // Helper to process deferred Bluetooth system default adoption
#if os(macOS)
    private func processPendingSystemDefaultIfNeeded(devices: [InputAudioDevice]) {
        guard let pending = pendingSystemDefaultInput else {
            logger.debug("🎧 processPendingSystemDefaultIfNeeded: no pending system default")
            return
        }
        guard let changedAt = lastSystemInputChangeAt else {
            logger.debug("🎧 processPendingSystemDefaultIfNeeded: missing lastSystemInputChangeAt, clearing pending")
            pendingSystemDefaultInput = nil
            lastSystemInputChangeAt = nil
            return
        }
        
        let age = Date().timeIntervalSince(changedAt)
        logger.debug("🎧 processPendingSystemDefaultIfNeeded: pending=\(pending.name) age=\(String(format: "%.2f", age))s devices.count=\(devices.count)")
        
            // Wait for a short delay so the Bluetooth input path can fully come online
        if Date().timeIntervalSince(changedAt) < bluetoothAdoptionDelay {
            return
        }
            // Ensure the pending device is still present in the current device list. If it's not
            // there yet, keep waiting for a short timeout so we don't race HAL while the Bluetooth
            // route is still coming online.
        if devices.first(where: { $0.id == pending.id }) == nil {
            let age = Date().timeIntervalSince(changedAt)
            if age < bluetoothAdoptionTimeout {
                logger.debug("🎧 Deferred Bluetooth default \(pending.name) not yet present in device list (age=\(String(format: "%.2f", age))s) – keeping pending")
                return
            } else {
                logger.info("🎧 Deferred Bluetooth default \(pending.name) still missing after \(String(format: "%.2f", age))s – clearing pending")
                pendingSystemDefaultInput = nil
                lastSystemInputChangeAt = nil
                return
            }
        }
            // Do not override an explicit user selection that happened after the system change
        guard !userPinnedSelection else {
            logger.info("🎧 Deferred Bluetooth default \(pending.name) ignored – user pinned \(self.selectedDevice.name)")
            pendingSystemDefaultInput = nil
            lastSystemInputChangeAt = nil
            return
        }
        logger.info("🎧 Adopting deferred Bluetooth system default input: \(pending.name) [id: \(pending.id)]")
        selectedDevice = pending
        selectedInputDeviceSubject.send(pending)
        userPinnedSelection = false
            // Reset per-engine health tracking for the newly adopted Bluetooth device
        resetSignalHealth()
        hasSeenNonSilentFrameForCurrentEngine = false
        didAttemptBluetoothFallbackForCurrentEngine = false
        silentCount = 0
        deadSilenceFrameCount = 0
            // Reset adaptive noise floor for the new system-selected device
        learnedNoiseFloor = -120
        learnedNoiseFloorSamples = 0
        noiseFloorLearnNotBefore = Date().addingTimeInterval(1.0)
            // Give auto-select a brief grace window and reset tap retry state
        inputAutoSelectGraceUntil = Date().addingTimeInterval(1.0)
        pendingTapRetry?.cancel(); pendingTapRetry = nil
        tapRetryCount = 0
            // Retarget engine/tap to the newly adopted device
        verifyMicPermissionThen { [weak self] in
            guard let self = self else { return }
            if self.engine.isRunning { self.engine.stop() }
            if self.tapInstalled {
                self.engine.inputNode.removeTap(onBus: 0)
                self.tapInstalled = false
            }
            if !self.isStarting { self.startEngine() }
        }
        pendingSystemDefaultInput = nil
        lastSystemInputChangeAt = nil
    }
#endif
    
    
#if os(macOS)
        /// When HAL/CoreAudio returns a device error (e.g. -10877), temporarily back off
        /// from device enumeration and route changes so the HAL plugin can recover.
    private var halBackoffUntil: Date?
    private func enumerateInputDevices() -> [InputAudioDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let statusSize = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize)
        guard statusSize == noErr else {
            logger.error("❌ HAL device list size query failed, status=\(statusSize)")
            if statusSize == -10877 {
                halBackoffUntil = Date().addingTimeInterval(1.5)
                logger.warning("⏸️ Entering HAL backoff for 1.5s due to HALDeviceError (-10877) [size]")
            }
            return []
        }
        
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        let statusData = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize, &ids)
        guard statusData == noErr else {
            logger.error("❌ HAL device list fetch failed, status=\(statusData)")
            if statusData == -10877 {
                halBackoffUntil = Date().addingTimeInterval(1.5)
                logger.warning("⏸️ Entering HAL backoff for 1.5s due to HALDeviceError (-10877) [data]")
            }
            return []
        }
        
        func inputChannelCount(_ id: AudioObjectID) -> UInt32 {
            var streamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var size: UInt32 = 0
            let stSize = AudioObjectGetPropertyDataSize(id, &streamAddr, 0, nil, &size)
            guard stSize == noErr, size > 0 else {
                if stSize == -10877 {
                    halBackoffUntil = Date().addingTimeInterval(1.5)
                    logger.warning("⏸️ Entering HAL backoff for 1.5s (stream config size) on id=\(id)")
                }
                return 0
            }
            
            let buf = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<Int8>.alignment)
            defer { buf.deallocate() }
            let stData = AudioObjectGetPropertyData(id, &streamAddr, 0, nil, &size, buf)
            guard stData == noErr else {
                if stData == -10877 {
                    halBackoffUntil = Date().addingTimeInterval(1.5)
                    logger.warning("⏸️ Entering HAL backoff for 1.5s (stream config data) on id=\(id)")
                }
                return 0
            }
            
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
            let stNameSize = AudioObjectGetPropertyDataSize(id, &nameAddr, 0, nil, &nameSize)
            guard stNameSize == noErr else {
                if stNameSize == -10877 {
                    halBackoffUntil = Date().addingTimeInterval(1.5)
                    logger.warning("⏸️ Entering HAL backoff for 1.5s (device name size) on id=\(id)")
                }
                return "Audio Device"
            }
            
            let ptr = UnsafeMutableRawPointer.allocate(byteCount: Int(nameSize), alignment: MemoryLayout<Int8>.alignment)
            defer { ptr.deallocate() }
            let stNameData = AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nameSize, ptr)
            guard stNameData == noErr else {
                if stNameData == -10877 {
                    halBackoffUntil = Date().addingTimeInterval(1.5)
                    logger.warning("⏸️ Entering HAL backoff for 1.5s (device name data) on id=\(id)")
                }
                return "Audio Device"
            }
            
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
                guard let def = self.systemDefaultInputDevice() else { return }
                
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
                    // Not forcing: only adopt the new system default automatically if we currently
                    // have no real selection (placeholder / none). If the user has already
                    // selected a device, keep that selection and just log the system change.
                if self.userPinnedSelection {
                    self.logger.info("🔔 System default input changed → keeping user-selected input: \(self.selectedDevice.name) [id: \(self.selectedDevice.id)] (new system default is \(def.name) [id: \(def.id)])")
                    return
                }
                let lowerName = def.name.lowercased()
                let isAirPods = lowerName.contains("airpods")
                let isBeats = lowerName.contains("beats")
                let isBluetoothHeadset = isAirPods || isBeats
                
                    // For Bluetooth headsets (AirPods / Beats), adopt the new system default
                    // immediately at the app level, but quiesce the engine and delay the actual
                    // engine restart so the SCO/HFP path can fully come online.
                if isBluetoothHeadset {
                        // Mark that a Bluetooth route change is in progress so other auto-healing
                        // logic (engine restarts, tap retries) stands down.
                    self.pendingSystemDefaultInput = def
                    self.lastSystemInputChangeAt = Date()
                    self.inputAutoSelectGraceUntil = Date().addingTimeInterval(self.bluetoothAdoptionDelay)
                    
                        // Adopt the new default as our current selection (no user pin)
                    self.selectedDevice = def
                    self.selectedInputDeviceSubject.send(def)
                    self.userPinnedSelection = false
                    
                    self.logger.info("🔔 System default input changed → adopting Bluetooth default \(def.name) [id: \(def.id)] and quiescing engine during route change")
                    
                        // Quiesce the current engine/tap so we’re not driving the old device
                        // while CoreAudio tears it down.
                    if self.engine.isRunning {
                        self.engine.stop()
                    }
                    if self.tapInstalled {
                        self.engine.inputNode.removeTap(onBus: 0)
                        self.tapInstalled = false
                    }
                    
                        // Reset per-engine / per-device state for the upcoming Bluetooth engine
                    self.resetSignalHealth()
                    self.hasSeenNonSilentFrameForCurrentEngine = false
                    self.didAttemptBluetoothFallbackForCurrentEngine = false
                    self.silentCount = 0
                    self.deadSilenceFrameCount = 0
                    
                        // Reset adaptive noise floor and tap retry state
                    self.learnedNoiseFloor = -120
                    self.learnedNoiseFloorSamples = 0
                    self.noiseFloorLearnNotBefore = Date().addingTimeInterval(1.0)
                    self.pendingTapRetry?.cancel()
                    self.pendingTapRetry = nil
                    self.tapRetryCount = 0
                    
                        // After a short delay (bluetoothAdoptionDelay), restart the engine on
                        // the new Bluetooth route.
                    let delay = self.bluetoothAdoptionDelay
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        guard let self = self else { return }
                        self.verifyMicPermissionThen { [weak self] in
                            guard let self = self else { return }
                            if self.engine.isRunning { self.engine.stop() }
                            if self.tapInstalled {
                                self.engine.inputNode.removeTap(onBus: 0)
                                self.tapInstalled = false
                            }
                            if !self.isStarting { self.startEngine() }
                            
                                // Route change complete – clear the pending flag so other
                                // watchdogs can resume normal behavior.
                            self.pendingSystemDefaultInput = nil
                            self.lastSystemInputChangeAt = nil
                        }
                    }
                    
                    return
                }
                    // No explicit user selection yet and not forcing: follow the new system default immediately
                self.selectedDevice = def
                self.selectedInputDeviceSubject.send(def)
                self.userPinnedSelection = false
                self.logger.info("🔔 System default input changed → adopting system default (no pinned selection): \(def.name) [id: \(def.id)]")
                
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

