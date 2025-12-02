# Project Structure

This document describes the full logical and physical structure of **AudioMonitorApp**, built for **macOS 26** and **Swift 6.2**.  
It focuses on clarity for future maintainers, contributors, and long-term evolution of the app.

---

## 📁 High-Level Layout

```
AudioMonitorApp/
 ├── Audio/
 │    ├── AudioManager.swift
 │    ├── AudioProcessor.swift
 │    ├── AudioDeviceInfo.swift
 │    └── AudioStats.swift
 │
 ├── ViewModel/
 │    └── AudioMonitorViewModel.swift
 │
 ├── Logging/
 │    ├── LogManager.swift
 │    ├── LogWriter.swift
 │    └── AdvancedLogViewerView.swift
 │
 ├── Views/
 │    ├── AudioMonitorView.swift
 │    ├── AudioStatsView.swift
 │    └── Components/
 │         └── VUMeterView.swift   (if split out)
 │
 ├── App/
 │    └── AudioMonitorApp.swift
 │
 └── Documentation/
       ├── Architecture.md
       ├── AudioManager.md
       ├── AudioProcessor.md
       ├── CoreAudioAndHAL.md
       ├── BluetoothHandling.md
       ├── VUMeterBehavior.md
       ├── Protocols.md
       ├── Concurrency.md
       └── BuildAndDebug.md
```

---

## 🧱 **Core Modules**

### **1. Audio Layer**
The low-level engine and DSP logic.

| File | Responsibility |
|------|----------------|
| **AudioManager.swift** | Device switching, AVAudioEngine lifecycle, HAL error handling, Bluetooth warm-up logic. |
| **AudioProcessor.swift** | Per-buffer DSP: dBFS, smoothing, RMS, peak detection, silence detection. |
| **AudioDeviceInfo.swift** | Immutable model representing an audio device (id, name, channels). |
| **AudioStats.swift** | Readings for VU meter and diagnostics (L/R dBFS, peaks, noise floor). |

This layer must remain **real-time safe** where required (`AudioProcessor.processBuffer()`).

---

### **2. ViewModel Layer**

| File | Description |
|------|-------------|
| **AudioMonitorViewModel.swift** | Owns and orchestrates AudioManager, exposes published properties to SwiftUI, handles UI logic, manages user selection, and logs transitions. |

This layer converts engine events into UI-safe state updates (actors + MainActor).

---

### **3. Logging Layer**

| File | Description |
|------|-------------|
| **LogManager.swift** | Aggregates logs from AudioManager, ViewModel, DSP, Bluetooth events. |
| **LogWriter.swift** | Writes structured log entries, timestamps, categories. |
| **AdvancedLogViewerView.swift** | In-app developer log viewer UI. |

Logs are written with minimal overhead; heavy formatting is deferred to UI.

---

### **4. SwiftUI Views**

| File | Description |
|------|-------------|
| **AudioMonitorView.swift** | Main dashboard with VU meters + device picker. |
| **AudioStatsView.swift** | Shows detailed L/R statistics. |
| **Components/** | Shared UI components, e.g. VU meter. |

Views are stateless; all logic is in ViewModel or AudioManager.

---

### **5. App Entry Point**

| File | Description |
|------|-------------|
| **AudioMonitorApp.swift** | App lifecycle, initializes ViewModel and LogManager. |

---

## 🏗 Build System Notes

- Requires **macOS 26** SDK  
- Requires **Swift 6.2 or newer**  
- Uses the new Swift concurrency model (actors, isolated classes, Sendable)  
- Deployment target matches latest macOS release (26.x)  

No external dependencies — 100% native Swift + CoreAudio + SwiftUI.

---

## 🧩 Design Principles

- **MVVM with isolated responsibilities**
- **Non-blocking audio thread** (no allocations in real-time path)
- **MainActor only for UI updates**
- **Recovery-first CoreAudio design**
- **Observability emphasis**: logs explain every device and engine transition
- **Testability**: AudioProcessor is pure logic → easy to unit test

---

## 🧭 Future Structure (Optional)
Possible additions:

```
Tests/
 ├── AudioProcessorTests.swift
 ├── AudioManagerMock.swift
 └── HALSimulationTests.swift
```

---

# End of Document

