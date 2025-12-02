# AudioMonitorApp  
A professional‑grade real‑time audio input monitor built for **macOS 16 (26.x)** using **Swift 6.2**, th latest Swift Concurrency model, and SwiftUI.  

AudioMonitorApp is engineered to handle complex CoreAudio & HAL behavior, high‑precision metering, and unstable Bluetooth audio routes (AirPods, Beats) — all while maintaining accurate, stable, low‑latency audio monitoring.

## ✨ Features

### 🎚️ Accurate, Professional VU Metering
- Real‑time **dBFS** measurement (L/R)  
- Analog‑style ballistic behavior (fast attack / slow release)  
- Needle‑like response curve modeled after 1970s hardware  
- Stereo processing (or mono if device reports it)  
- Overmodulation detection (clip indicator shown in red)  
- Silence detection & noise‑floor learning  
- –120 dBFS safety floor for unstable devices (Bluetooth warm‑up)

### 🎧 Advanced Input Device Management

Powered by a custom **AudioManager** built on AVAudioEngine + CoreAudio HAL:

- Live monitoring of **system default input**  
- Grace windows preventing rapid reconfiguration  
- Intelligent **Bluetooth warm‑up** (200–600 ms buffering)  
- Recovery from HAL failures:
  - `!obj`
  - `!dev`
  - `-10877` (AudioUnit render warning)
  - `TooManyFramesToProcess`
- Fully clean teardown and safe engine restarts  
- Removes taps before installing new ones  
- Learns per‑device noise floors  


### 🩺 Diagnostics & Logging

Includes a full in‑app diagnostics suite:

- Real‑time log stream  
- Device‑change timeline  
- State machine transitions  
- AVAudioEngine event visibility  
- HAL error codes surfaced clearly  
- Bluetooth warm‑up tracking  
- Per‑frame AudioStats  
- Searchable, scrollable **AdvancedLogViewerView**


### 📊 Real-Time Audio Processing (AudioProcessor.swift)

- dBFS computation per channel  
- Attack/release smoothing  
- Zero‑crossing peak verification  
- Adaptive noise‑floor logic  
- Silence & clipping detection  
- Bluetooth stabilization mode  
- Safety clamp at **–120 dBFS** when device is unstable


### ⚡ Modern Swift Concurrency (Swift 6.2)

This project is fully updated for the new Swift 6.2 requirements:

- Strict **Sendable** enforcement  
- Isolation domains (MainActor, audio thread isolation)  
- Async device polling  
- Actor‑safe logging system  
- Nonisolated audio callback paths  
- Avoids undefined behavior across threads


## 🧱 Architecture Overview (MVVM + Audio Layer)

### **Model**
- `AudioStats`  
- `AudioDeviceInfo`  
- `LogEntry`  
- `AudioProcessor`  
- `LogManager`  

### **ViewModel**
- `AudioMonitorViewModel`
  - Owns `AudioManager`
  - Publishes device list & active device
  - Publishes VU levels
  - Coordinates logging, stabilization, warm‑up
  - Provides UI‑ready state

### **View**
- `AudioMonitorView`
- `AdvancedLogViewerView`
- `AudioStatsView`
- (Future) macOS Widget

## 🎧 How Audio Input Works

### 1. AVAudioEngine Input Tap
The engine pulls PCM buffers → AudioProcessor computes real‑time levels.

### 2. Device Switching Pipeline
When macOS changes the **default input**:

1. Detect CoreAudio notification  
2. Freeze UI selection unless user pinned a device  
3. Apply grace‑window (200–600 ms)  
4. Quiesce engine  
5. Remove tap  
6. Install new tap  
7. Begin noise‑floor learning  
8. Resume monitoring

Bluetooth devices get an extended warm‑up window.

### 3. HAL Error Recovery

The app catches and survives:

| Error | Meaning |
|-------|---------|
| `!obj` | HAL object vanished mid‑transaction |
| `!dev` | Device disappeared while IOProc active |
| `-10877` | Render callback produced invalid audio |
| `TooManyFramesToProcess` | Engine forced into oversized render cycle |

Engine is restarted safely, with structured logging.

### 4. Adaptive Noise Floor Learning
Noise floor is learned during first valid frames.  
Until stable: all frames are forced to **–120 dBFS**.


## 🧪 Debugging Tools

### Inline Live Log Viewer
Displays:

- systemDefaultInput events  
- HAL warnings  
- Audio engine restarts  
- Bluetooth device warm‑up timeline  
- Tap failures  
- Per‑frame statistical summaries  

### Persistent Logs
Saved automatically for later review.


## 📦 Project Structure

```
AudioMonitorApp/
 ├── AudioManager.swift
 ├── AudioProcessor.swift
 ├── AudioMonitorViewModel.swift
 ├── LogManager.swift
 ├── LogWriter.swift
 ├── AudioMonitorView.swift
 ├── AdvancedLogViewerView.swift
 ├── AudioStatsView.swift
 ├── AudioMonitorApp.swift
 └── README.md
```


## 🛠 Build Requirements
- **macOS 16 (26.x)**  
- **Xcode 16+**  
- **Swift 6.2**  
- SwiftUI  
- Microphone permission  


## 🚀 Roadmap
- macOS widget (live dBFS meter)  
- Historical graphing + export  
- LUFS/RMS DSP modes  
- Log export  
- Test suite for DSP & AudioManager  


## 📄 License
MIT (customize if needed)


## 🤝 Contributions
Open to PRs and issues.


## 🧡 About This Project
AudioMonitorApp is built as a **professional diagnostic tool** for engineers, musicians, podcasters, and developers who need transparent and reliable insight into the macOS CoreAudio input pipeline.
