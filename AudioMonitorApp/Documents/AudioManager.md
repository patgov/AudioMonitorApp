# AudioManager

AudioManager – Device Control, Engine Lifecycle & CoreAudio/HAL Integration
===========================================================================

`AudioManager` is the central controller for all real-time audio I/O operations
in AudioMonitorApp.  
It owns the `AVAudioEngine`, manages the input route, installs and removes
taps, and coordinates warm-up, retries, fallbacks, and HAL-level recovery.

This document explains:

- How AudioManager works  
- Why certain behaviors exist (Bluetooth warm-up, grace windows, etc.)
- How it interacts with CoreAudio and HAL  
- What guarantees it provides to the ViewModel and UI  


---

# 1. Responsibilities Overview

AudioManager is responsible for:

### ✔ Audio Engine Lifecycle  
- Configure and start `AVAudioEngine`
- Install and remove input taps
- Stop, quiesce, or fully reset the engine when routes change

### ✔ Input Device Management  
- Fetch available input devices
- Track the current selected device
- Honor user-pinned selection
- Monitor system default input changes
- Validate devices before selecting them

### ✔ Bluetooth-Aware Routing  
- Defer adoption of newly discovered Bluetooth mics (AirPods/Beats)
- Warm-up periods to allow route stabilization
- Noise-floor learning before enabling visible meter output
- Fallback if Bluetooth is digitally silent

### ✔ Error Handling & Recovery  
Handles transient and persistent CoreAudio/HAL failures such as:

| Error | Meaning |
|-------|---------|
| `-10877` | Render callback failed (common when device switches mid-buffer) |
| `!obj` | HAL object disappeared (Bluetooth teardown) |
| `!dev` | Device terminated during IOProc |
| `TooManyFramesToProcess` | Engine given more frames than supported |

The manager logs all such events and uses controlled retry strategies.

### ✔ Publishing Events & Stats  
- Publishes current device, engine status, error flags
- Provides processed audio samples through `AudioProcessor`
- Emits structured log entries to `LogManager`

---

# 2. Lifecycle State & Flags

AudioManager tracks several carefully managed flags to avoid re-entrancy
problems inside AVAudioEngine and HAL:

| Flag | Purpose |
|------|---------|
| `isStarting` | Prevents overlapping engine start attempts |
| `tapInstalled` | Ensures the input tap only exists once |
| `pendingSystemDefaultInput` | Stores system default changes during grace windows |
| `inputAutoSelectGraceUntil` | Prevents rapid reselects when devices flap |
| `userPinnedSelection` | Locks routing until user changes device |
| `lastSuccessfulDeviceID` | Prevents stale device IDs from being reused |

These flags are critical when interacting with Bluetooth, which rapidly
connects/disconnects and triggers HAL resets.

---

# 3. Device Selection Logic

## 3.1 Automatic Selection  
When the user does not pin a device, AudioManager:

1. Detects system default input changes  
2. Applies a **grace window** (200–600 ms)  
3. If device is stable, adopts the system default  
4. Restarts engine with new configuration  

## 3.2 User-Pinned Selection  
If the user manually selects a device:

- System changes are ignored
- If macOS forces a new default device, AudioManager restores the pinned one
- A flag (`forceSystemDefaultToSelected`) ensures macOS follows the app’s choice

## 3.3 Bluetooth Special Handling  
When a Bluetooth device (AirPods/Beats) becomes default:

- AudioManager does **not** immediately switch
- Instead:
  - Records it as `pendingSystemDefaultInput`
  - Quiesces engine
  - Waits for warm-up
  - Adopts the device only after the route stabilizes

This prevents HAL crashes from rapidly switching BT/USB/Built-in.

---

# 4. Engine Start / Stop Sequence

## 4.1 Start Sequence  
1. Verify mic permission  
2. Select valid device (user-pinned or system default)  
3. Reset flags  
4. Configure engine format  
5. Install input node tap  
6. Start engine  
7. Begin pulling buffers and sending them to AudioProcessor  

Retry logic applies if:
- Tap fails to install  
- Engine fails to start  
- HAL returns `-10877`  

## 4.2 Stop Sequence  
1. Remove tap if installed  
2. Stop the engine  
3. Clear pending input, retries, and locks  

---

# 5. Input Tap Behavior

The tap (AVAudioNodeTapBlock) is the heart of audio acquisition:

- Receives each `AVAudioPCMBuffer`  
- Checks for device validity  
- Sends audio frames to `AudioProcessor`  
- Publishes `AudioStats` to ViewModel  
- Detects silence, clipping, and non-zero peaks  

If a Bluetooth mic produces only `−120 dBFS` for too long:
- Considered "digitally silent"  
- Log warning  
- Trigger fallback to more stable device  

---

# 6. Bluetooth Warm-Up & Silence Detection

Bluetooth mics often produce invalid buffers for the first ~200–500 ms.

### Warm-Up Steps:
1. System default input changes  
2. AudioManager stores BT device as pending  
3. Engine quiesces => stops tap & engine  
4. A delay allows the BT audio subsystem to stabilize  
5. AudioManager adopts device and restarts engine  
6. AudioProcessor holds meter at **−120 dBFS** until a real frame arrives  

### Silence Threshold  
If after ~60–90 frames:
- Output remains at −120 dBFS  
→ Fallback initiated

---

# 7. HAL Error Handling

All HAL errors are logged along with context.

## Example Logic Flow  
When receiving `-10877`:
```
if retryCount < retryLimit {
    log("HAL -10877, retrying engine start")
    stopEngine()
    startEngine()
}
else {
    log("HAL -10877, exceeded retry limit, failing")
}
```

AVAudioEngine’s internal state machine is sensitive to rapid
reconfiguration, so all retries are rate-limited.

---

# 8. Logging Integration

Every major step emits log events:

- Device list fetch  
- System default changes  
- Tap install/remove  
- Engine start, stop, restart  
- HAL failure context  
- Bluetooth warm-up start/finish  
- Fallback decisions  

These logs feed:
- **LogManager**  
- **AdvancedLogViewerView**  

---

# 9. Responsibilities Summary

| Area | Responsibility |
|------|---------------|
| Engine Control | Start/stop/reset engine safely |
| Device Mgmt | Track system default & user-selected inputs |
| Routing Decisions | Bluetooth deferral, fallback logic |
| Buffer Acquisition | Receive samples from CoreAudio |
| Processing | Forward to AudioProcessor |
| Diagnostics | Log every significant event |
| UI Integration | Publish device list, levels, errors |

AudioManager is intentionally isolated from UI and DSP logic.  
It is the “traffic controller” for the entire app.

---

# 10. Future Improvements

Planned architectural extensions:

- Abstracted device graph representation  
- More deterministic retries using a backoff scheduler  
- Formal state machine modeling engine states  
- Optional low-latency mode for pro audio gear  
- Better detection of aggregate/split devices  

---

