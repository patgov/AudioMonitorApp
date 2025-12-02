# Protocols.md  
### Internal Protocols and Abstractions Used in AudioMonitorApp

This document describes the protocols used throughout **AudioMonitorApp**, why they exist, and how each contributes to clean architecture, testability, and separation of concerns.

Protocols provide lightweight abstraction around components that interact with:

- CoreAudio / AVAudioEngine  
- Device management  
- Logging  
- Audio processing  
- View-model communication  

This ensures the app remains maintainable and modular even as advanced audio handling (HAL errors, Bluetooth warm-up, tap recovery, etc.) grows in complexity.

---

# 1. `AudioProcessing` Protocol  
Implemented by: **AudioProcessor.swift**

### Purpose  
Defines the real-time audio transformation and analysis pipeline used by the VU meters.

### Responsibilities  
- Convert raw PCM buffers to dBFS values  
- Apply attack/release smoothing  
- Maintain noise-floor learner  
- Detect clipping and silence  
- Provide well-structured results to the UI  

### Protocol  
```swift
protocol AudioProcessing {
    func processBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime)
    var latestStats: AudioStats { get }
}
```

### Notes  
This abstraction allows you to:
- Mock audio input for UI previews  
- Swap in alternative processors (RMS, LUFS, calibrated meters) later  
- Unit-test smoothing and silence detection without a real microphone  

---

# 2. `AudioManaging` Protocol  
Implemented by: **AudioManager.swift**

### Purpose  
Abstracts all interaction with AVAudioEngine, CoreAudio, device switching, HAL error recovery, and tap lifecycle.

### Responsibilities  
- Start/stop the engine  
- Install/remove input taps  
- Watch for system default input changes  
- Defer Bluetooth adoption  
- Emit device lists  
- Notify the view model about state changes

### Protocol  
```swift
protocol AudioManaging: AnyObject {
    var selectedDevice: AudioDeviceInfo { get }
    var availableDevices: [AudioDeviceInfo] { get }
    func start()
    func stop()
    func refreshInputDevices()
    func selectDevice(_ device: AudioDeviceInfo)
    var onStats: ((AudioStats) -> Void)? { get set }
}
```

### Notes  
`AudioMonitorViewModel` doesn’t need to know about HAL, AudioObjectPropertyListeners, or render-callback errors.  
It just commands an `AudioManaging` object.

---

# 3. `LogWriting` Protocol  
Implemented by: **LogWriter.swift**

### Purpose  
Provides a simple interface for adding new entries to the app’s internal debugging log.

### Responsibilities  
- Append timestamped events  
- Differentiate subsystem categories  
- Persist logs for viewing  

### Protocol  
```swift
protocol LogWriting {
    func log(_ message: String, subsystem: String, category: String)
}
```

This allows:
- Redirecting logs to disk  
- Redirecting to in-app UI viewer  
- Potential future: sending logs to cloud storage  

---

# 4. `DeviceProviding` Protocol  
Implemented by: **AudioManager.swift** (device-specific extensions)

### Purpose  
Ensures consistent representation of macOS/iOS audio devices.

### Responsibilities  
- Convert CoreAudio device IDs to app-friendly `AudioDeviceInfo`  
- Provide canonical device name, sample rate, and channel count  

### Protocol  
```swift
protocol DeviceProviding {
    func fetchDevices() -> [AudioDeviceInfo]
    func systemDefaultInputDevice() -> AudioDeviceInfo?
}
```

---

# 5. `StatsPublishing` Protocol  
Provided informally by **AudioProcessor → AudioManager → ViewModel**

### Purpose  
Defines the unidirectional flow of live audio data toward the UI.

### Flow  
```
AudioProcessor → AudioManager → AudioMonitorViewModel → SwiftUI Views
```

### Responsibilities  
- Publish `AudioStats`  
- Avoid backpressure  
- Support 60 FPS UI refresh  
- Maintain thread safety across CoreAudio → main thread

### Conceptual Protocol  
```swift
protocol StatsPublishing {
    var onStats: ((AudioStats) -> Void)? { get set }
}
```

---

# 6. `ViewModelUpdating` Protocol  
(Not formal, but recommended pattern)

Defines how the view model reacts to:

- Device list changes  
- Engine restarts  
- Bluetooth warm-up events  
- HAL errors  
- Tap installation failures  
- Noise floor resets  

### Pattern  
```swift
protocol ViewModelUpdating {
    func updateDevices(_ devices: [AudioDeviceInfo])
    func updateSelectedDevice(_ device: AudioDeviceInfo)
    func updateStats(_ stats: AudioStats)
    func updateEngineState(isRunning: Bool)
}
```

Currently implemented implicitly inside `AudioMonitorViewModel`.

---

# 7. Why Use Protocols Here?

## Benefits

### ✔ Better Testability  
You can mock the AudioManager and simulate any scenario:
- AirPods switching behavior  
- HAL throwing `!obj`  
- Bluetooth zero-silence warm-up  
- Overload errors  
- Missing devices  

### ✔ Cleaner Architecture  
The ViewModel only understands:
- Stats  
- Device lists  
- State changes  
It does *not* know:
- About HALC logs  
- About -10877 render failures  
- About AudioObjectPropertyListener callbacks  

### ✔ Safer Concurrency  
CoreAudio happens on:
- Real-time threads  
- Secondary dispatch queues  
- The main actor  

Protocols allow controlled data flow boundaries.

### ✔ Future-proof  
You could add in future:

- System output monitoring  
- Multi-input merging  
- LUFS processor  
- DSP plugins (AUv3)  
- Calibrated meters  

…all without rewriting the view layer.

---

# 8. Summary

The protocols in this project are not merely organizational—they enforce a robust **audio pipeline architecture** that separates:

- Real-time DSP  
- Device/HAL management  
- Logging  
- State updates  
- UI rendering  

This ensures AudioMonitorApp remains a professional, extensible tool for audio engineering and diagnostics.

---
