# Build and Debug Guide

This guide describes how to build, debug, and analyze **AudioMonitorApp** on macOS 26 using Xcode 16+.

---

## 🛠 Build Requirements

- **macOS 26**
- **Xcode 16 or newer**
- **Swift 6.2**
- **Microphone access enabled**
- Running on Apple Silicon recommended (faster CoreAudio debug cycles)

---

## 📦 Building the App

1. Clone the project:
   ```bash
   git clone https://github.com/<your-repo>/AudioMonitorApp.git
   ```

2. Open in Xcode:
   ```
   open AudioMonitorApp.xcodeproj
   ```

3. Ensure the **Signing & Capabilities** tab has:
   - *Microphone* capability  
   - Team code signing selected  

4. Select **My Mac (Designed for Mac)** as the run destination.

5. Run:
   ```
   ⌘ + R
   ```

---

## 🎧 Debugging Audio Issues

### 1. **Engine failed to start**  
Common reasons:
- macOS route change mid-startup  
- HAL object disappeared (`!obj`)  
- Bluetooth device not ready  
- AVAudioSession init delayed  

The app logs these in **AdvancedLogViewerView**.

---

### 2. **Device Switching Delays**
When switching between:
- USB → AirPods  
- AirPods → internal  
- USB interfaces  

macOS often:
- Rebuilds HAL objects  
- Tears down Bluetooth SCO/LC3 stack  
- Sends out-of-order IOProc messages  

The app will log events such as:
```
HALC_ProxyIOContext::IOWorkLoop: out of order message
throwing -10877
AudioObjectSetPropertyData: no object with given ID
```

These are normal during transitions — the app recovers automatically.

---

### 3. **Buffer Tap Not Firing**
Symptoms:
- Levels stuck at −120 dBFS  
- No peaks detected  
- Bluetooth silent after connection  

AudioProcessor will report:
```
peakNonZero = false
```

**Fix:**  
Stop engine → restart → reattach tap. AudioManager does this automatically.

---

## 🧪 Debug Tools

### **Inline Log Viewer**
Accessible from inside the app. Displays:

- Engine start/stop  
- Device ID changes  
- HAL error codes  
- Pending default input adoption  
- Bluetooth warm-ups  
- Silence detection  
- Interruption events  

Logs include timestamps and categories.

---

### **Xcode Debugging Tips**

#### Enable CoreAudio HAL Debug Logging
In terminal:
```bash
sudo killall coreaudiod
```
Then relaunch app — HAL logs appear in Console.app under subsystem `com.apple.audio`.

#### Use Debug Memory Graph
Audio taps and AVAudioEngine chains must not leak.  
Use **Xcode → Debug → Memory Graph**.

---

## 🧲 Troubleshooting HAL Errors

### ❗ `-10877` (Render callback failed)
Occurs when:
- Device disappears  
- HAL I/O thread changes beat timing  
- Bluetooth stack renegotiates codec  

App responds by:
- Quiescing engine  
- Restarting with back-off  
- Reattaching taps safely  

---

### ❗ `!obj` / `!dev`
CoreAudio plugin tried to access a device that was destroyed.

The app logs and automatically retries.

---

### ❗ “TooManyFramesToProcess”
Usually due to:
- Buffer mismatch  
- AirPods LC3 renegotiation  
- Bluetooth dropouts  

Engine restart resolves it automatically.

---

## 🛡 Release Build Notes

Enable these settings in **Build Settings**:

| Setting | Value |
|--------|--------|
| Optimization Level | `-O` |
| Swift Concurrency Checking | Enabled |
| Dead Code Stripping | On |
| Enable Hardened Runtime | On |
| Strip Debug Symbols | On for Release |

---

## 🚀 Profiling

### Audio Processing Profiling
Use Time Profiler:
- Search for `AudioProcessor.processBuffer`
- Confirm < 0.1 ms execution time
- Look for allocations (should be zero)

### Bluetooth Delay Profiling
Use Signpost logging (optional future enhancement).

---

## 📦 Distribution

Export via:
```
Product → Archive → Distribute App
```

Recommended: Developer ID distribution for external testers.

---

# End of Document

