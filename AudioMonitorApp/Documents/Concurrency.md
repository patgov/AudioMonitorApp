# Concurrency in AudioMonitorApp  
### Threads, Queues, and Safety Around CoreAudio, AVAudioEngine, and SwiftUI

AudioMonitorApp does **real-time audio processing** while also reacting to:

- Device changes (USB ↔ Bluetooth ↔ iPhone mic)
- HAL / CoreAudio errors (`!obj`, `!dev`, `-10877`, etc.)
- AVAudioEngine route changes and restarts
- SwiftUI view updates and logging

This document explains how concurrency is handled so the app stays **responsive, safe, and glitch-resistant**.

---

## 1. High-Level Threading Model

At a high level, the app has three types of work:

1. **Real-time audio I/O**
   - CoreAudio / AVAudioEngine render callbacks
   - Input node taps (`installTap` on `inputNode`)
   - Must be **fast, non-blocking, and allocation-minimal**

2. **Control & state changes**
   - Starting / stopping the audio engine
   - Switching devices
   - Responding to system default input changes
   - Retrying taps, handling HAL errors

3. **UI & logging**
   - Updating SwiftUI views
   - Publishing `AudioStats` to the VU meters
   - Recording logs and diagnostics

### Conceptual Flow

```text
[CoreAudio RT Thread]  --->  [AudioProcessor]  --->  (callback)  --->  [AudioManager]
                                                                    |
                                                                    v
                                                             [Main Actor / ViewModel]
                                                                    |
                                                                    v
                                                                [SwiftUI Views]
                                                                

2. Audio Engine and Tap Concurrency

2.1 Real-Time Audio Callbacks

AVAudioEngine uses real-time threads to call the input tap closure with AVAudioPCMBuffer + AVAudioTime.

Inside the tap:
    •    The buffer is passed to AudioProcessor (pure Swift processing, NO blocking I/O).
    •    The processor computes:
    •    dBFS per channel
    •    Smoothed VU values
    •    Clipping / silence flags
    •    Noise floor updates
    •    The result is forwarded via a lightweight callback (onStats) to AudioManager.

Key rules in the tap:
    •    ✅ No disk I/O
    •    ✅ No logging to console/UI
    •    ✅ No locks if avoidable
    •    ✅ No blocking on other queues
    •    ✅ Do not touch SwiftUI or view models directly

All UI and logging must be dispatched out of the RT path.

⸻

3. AudioManager Concurrency

AudioManager is the concurrency hub between:
    •    CoreAudio / AVAudioEngine
    •    Device change listeners
    •    AudioProcessor
    •    ViewModel & logging

3.1 System Default Input Listener

The app registers a CoreAudio property listener:

AudioObjectAddPropertyListenerBlock(
    AudioObjectID(kAudioObjectSystemObject),
    &addr,
    nil,
    callback
)

Inside that callback:
    1.    The listener runs on a CoreAudio-managed queue (not guaranteed main).
    2.    The code immediately hops to the main queue:

DispatchQueue.main.async { [weak self] in
    // Safe: UI, state, engine control, logging
}

This ensures:
    •    💡 All engine start/stop operations happen on the main thread.
    •    💡 Device selection & selectedDevice updates are main-thread consistent.
    •    💡 SwiftUI view model receives changes on the main actor.

3.2 Route Changes & Bluetooth Warm-Up

When system default input changes:
    •    If switching to Bluetooth (AirPods / Beats):
    •    The app marks a pending Bluetooth default.
    •    It sets a grace window (bluetoothAdoptionDelay, ~200–600 ms).
    •    The engine may be stopped or quiesced during the transition.
    •    A delayed restart is scheduled on the main queue (DispatchQueue.main.asyncAfter).

This prevents:
    •    Taps being installed while the device is still warming up.
    •    HAL errors like !obj and -10877 during unstable device states.
    •    Repeated start/stop thrashing.

⸻

4. ViewModel and SwiftUI (Main Actor)

AudioMonitorViewModel is effectively main-actor bound:
    •    Owns references to:
    •    AudioManager
    •    Logs / recent stats
    •    Current device selection
    •    Receives stats via a closure callback or Combine-style publisher from AudioManager.
    •    Publishes properties for SwiftUI views (@Published / @MainActor semantics).

Rules
    •    All @Published properties must be updated on the main thread.
    •    Device list updates, selection changes, and log additions must be performed on main.
    •    No heavy computation in the view model; defer to AudioProcessor and AudioManager.

⸻

5. Logging Concurrency

Logging is high volume when diagnosing CoreAudio issues, so it’s structured carefully:
    •    Log calls from real-time or CoreAudio queues are minimized and/or performed through
inexpensive mechanisms.
    •    UI log viewer (AdvancedLogViewerView) reads from an in-memory buffer or SwiftData store,
updated from the main thread.
    •    Background queues can be used for writing logs to disk, but they must never block
the audio RT path.

General pattern:

func logAsync(_ message: String) {
    DispatchQueue.main.async { [weak self] in
        self?.logManager.append(message)
    }
}

Or, if disk writes are heavy:

backgroundLogQueue.async {
    // Encode + write log entry to disk
}


⸻

6. Handling CoreAudio / HAL Errors Safely

The app sees a variety of CoreAudio logs and errors:
    •    !obj – object disappeared (device died / unplugged)
    •    !dev – device unavailable for IOProc teardown / creation
    •    -10877 – AudioUnit render callback failed
    •    Out-of-order IOContext messages from HALC

Concurrency Strategy:
    1.    Never panic in real-time callbacks.
    •    On HAL errors, mark state and schedule corrective action on main.
    2.    Quiesce before reconfiguration.
    •    Stop the engine on the main thread.
    •    Remove input taps.
    •    Clear counters / retry state.
    •    Then restart once the system is stable.
    3.    Retry with backoff (if implemented).
    •    Short delay (e.g., 0.3–0.6s).
    •    Reset tapRetryCount if restart succeeds.

⸻

7. Common Patterns Used

7.1 Main-Actor Handoffs

From CoreAudio or background callback → to main:

DispatchQueue.main.async { [weak self] in
    guard let self else { return }
    self.refreshInputDevices()
    self.selectedDevice = def
    self.startEngineIfNeeded()
}

7.2 Delayed Operations After Route Change

DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
    guard let self else { return }
    self.verifyMicPermissionThen {
        if self.engine.isRunning { self.engine.stop() }
        // Remove tap, reset flags, restart engine, etc.
    }
}

This allows AVAudioSession / CoreAudio to fully settle before touching the engine.

⸻

8. Concurrency Gotchas and How AudioMonitorApp Avoids Them

❌ Calling UI / SwiftUI from RT threads

✅ All UI updates are dispatched to main.

❌ Logging heavily from render callbacks

✅ Processing and logging are split; logs are sent from main or a background queue.

❌ Switching devices while engine is mid-render

✅ Engine is stopped / quiesced, taps removed, then restarted on main after a delay.

❌ Bluetooth inputs treated like wired USB

✅ Special Bluetooth path:
    •    Defer adoption
    •    Grace window
    •    Noise floor pinned at –120 dBFS until real frames arrive

❌ Race conditions on selected device or device list

✅ These are mutated on main only, and used by background tasks in read-only ways.

⸻

9. Guidelines for New Code

When adding new features (widgets, recording, additional meters, etc.):
    1.    Assume CoreAudio callbacks are hard real-time.
    •    Don’t block, allocate heavily, or touch UI.
    2.    Constrain state mutations to the main thread.
    •    Device selection
    •    Engine lifecycle
    •    ViewModel updates
    3.    Use dedicated queues for heavy work.
    •    File I/O
    •    Log persistence
    •    Analysis beyond simple per-buffer DSP
    4.    Respect Bluetooth quirks.
    •    If handling new Bluetooth devices, reuse the warm-up / grace patterns.
    5.    Keep dependencies flowing in one direction:

CoreAudio → AudioProcessor → AudioManager → ViewModel → Views

Never call back up from Views down into CoreAudio threads directly.

⸻

10. Summary

Concurrency in AudioMonitorApp is built around a few core principles:
    •    Real-time safety (no heavy work in taps)
    •    Main-thread control for engine and device state
    •    Clear handoffs from CoreAudio threads to SwiftUI
    •    Graceful error handling for HAL and Bluetooth quirks

Following these patterns keeps the app stable even under:
    •    Rapid device plugging/unplugging
    •    Bluetooth connect/disconnect
    •    HAL internal overloads and out-of-order messages

This makes AudioMonitorApp a reliable tool for real-time monitoring in demanding audio environments.

Once you paste that, your `Concurrency.md` will be complete and consistent with the rest of the docs we’ve been building.

# Concurrency in AudioMonitorApp  
### Threads, Queues, Real‑Time Safety, and CoreAudio/HAL Interactions

AudioMonitorApp coordinates **real‑time DSP**, **device switching**, **HAL error recovery**, and **SwiftUI UI updates** without dropping frames or freezing during Bluetooth transitions.  
This enhanced document provides deeper insight into the concurrency model, adds diagrams, and formalizes rules for future development.

---

## 1. High‑Level Architecture of Concurrency

AudioMonitorApp can be visualized as three cooperating concurrency layers:

```
        ┌──────────────────────────────────────────────────────┐
        │              CoreAudio Real‑Time Thread              │
        │  • Input Tap                                         │
        │  • Render callbacks (hard real‑time)                 │
        │  • Must never block, log, or allocate heavily        │
        └──────────────────────────────────────────────────────┘
                        │       (stats)
                        ▼
        ┌──────────────────────────────────────────────────────┐
        │                  AudioManager Layer                   │
        │  • CoreAudio property listeners                      │
        │  • Route changes, device selection                   │
        │  • Bluetooth warm‑up + stabilization delays          │
        │  • Engine start/stop (main thread)                   │
        └──────────────────────────────────────────────────────┘
                        │       (Published state)
                        ▼
        ┌──────────────────────────────────────────────────────┐
        │                    SwiftUI / ViewModel               │
        │  • Receives stats                                    │
        │  • Updates VU meters / UI                            │
        │  • Manages logs                                      │
        └──────────────────────────────────────────────────────┘
```

Each layer has strict rules about what operations it may perform (detailed below).

---

## 2. Real‑Time Audio Callbacks (CoreAudio RT Thread)

The input tap is the **busiest and most timing‑sensitive** part of the app.

### Rules for Real‑Time Safety
Inside the tap closure:

- **❌ No SwiftUI**
- **❌ No logging**
- **❌ No locks**
- **❌ No sleeping / delays**
- **❌ No AVAudioEngine reconfiguration**
- **❌ No touching global mutable state**

Instead:

- **✔ Pure DSP**
- **✔ Lightweight buffer access**
- **✔ Pass results outward via callback (non‑blocking)**

### What happens inside the tap:
1. Convert buffer → float channel data.
2. Compute:
   - instantaneous power (dBFS)
   - smoothed VU values (attack/release)
   - clipping status
   - silence/noise‑floor tracking
3. Emit results via:

```
onStats(AudioStats)
```

This callback returns immediately, handing off to non‑RT code.

---

## 3. AudioManager Concurrency Model  
AudioManager is the **control tower** between real‑time DSP and the rest of the app.

### Key Responsibilities
- Reacting to system default input changes  
- Handling Bluetooth stabilization  
- Starting/stopping AVAudioEngine safely  
- Retrying taps when HAL errors occur  
- Delivering stats to the ViewModel  
- Ensuring thread‑safe state mutations  

### Main‑thread binding
All engine operations happen on the **main thread**:

```
DispatchQueue.main.async {
    self.startEngine()
}
```

This prevents:
- Engine corruption
- AVAudioEngine calling start/stop from multiple queues
- Race conditions during device teardown

---

## 4. System Default Input Listener (CoreAudio → Main)

CoreAudio triggers property listeners on **non‑main** queues:

```
AudioObjectAddPropertyListenerBlock(... callback)
```

Inside callback:
1. The app immediately hops to **main**:
```
DispatchQueue.main.async { ... }
```
2. AudioManager evaluates:
   - whether user pinned a device
   - whether device is Bluetooth  
   - timing of last change (grace window)

This ensures consistent device selection logic.

### Bluetooth Path: Deferred Adoption  
Bluetooth devices (AirPods/Beats) report quickly but are **not immediately ready**.

The app:
- stores `pendingSystemDefaultInput`
- extends `inputAutoSelectGraceUntil`
- **delays adoption ~200–600ms**
- restarts engine only when stabilized

This is crucial for avoiding:
- `!obj` errors  
- `!dev` IOProc failures  
- render callback `-10877` crashes  
- AirPods boot‑sequence silence frames

---

## 5. ViewModel + Main Actor Enforcement

`AudioMonitorViewModel` is effectively main‑actor only.

### Why:
- SwiftUI requires main‑thread updates  
- @Published must emit from main  
- Device list and selectedDevice are shared state  

Every public method that mutates view model state is main‑thread bound implicitly via SwiftUI's runtime.

### Stats Flow (Thread Diagram)

```
CoreAudio RT Thread
       │
       ▼
AudioProcessor  (DSP only)
       │ onStats(stats)
       ▼
AudioManager (main queue)
       │ publish
       ▼
ViewModel (main actor)
       │ @Published
       ▼
SwiftUI Views
```

---

## 6. Logging Concurrency

Logging must **never** interfere with audio.

### Strategy
- Real‑time threads → minimal/no logging  
- Main thread → UI log buffer  
- Background queue → disk I/O (optional)

Example:

```
logQueue.async {
    writeToDisk()
}
```

The UI viewer only reads from in‑memory logs updated on main.

---

## 7. HAL Error Handling & Recovery (Concurrency-Safe)

HAL emits many transient errors during:
- Bluetooth transitions
- USB unplug events
- Internal reconfiguration cycles

Errors handled:
| Error | Description |
|-------|-------------|
| `!obj` | Unknown / missing HAL object (device disappeared) |
| `!dev` | IOProc teardown failed |
| `-10877` | Render callback failed |
| `TooManyFramesToProcess` | Engine asked for > max buffer size |
| Out-of-order IOWorkLoop messages | HAL context timing mismatch |

### Recovery Pattern
1. **Main thread**: stop engine  
2. Remove taps  
3. Reset retry counters  
4. Delay (200–600ms)  
5. Restart engine  
6. Reinstall tap when stable  

Never attempt recovery on a CoreAudio queue.

---

## 8. Typical Concurrency Patterns Used Throughout the App

### 8.1 Main-thread updates from background

```
DispatchQueue.main.async {
    self.refreshInputDevices()
}
```

### 8.2 Delayed restarts after route changes

```
DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
    self.restartEngine()
}
```

### 8.3 Background logging queue

```
backgroundLogQueue.async {
    self.saveLogsToDisk()
}
```

### 8.4 Avoiding device-selection races

Device selection happens **only on main**.

CoreAudio listener threads only *inform* the main thread; they never directly mutate app state.

---

## 9. Concurrency Pitfalls Avoided by AudioMonitorApp

| Pitfall | App Behavior |
|---------|--------------|
| UI updates from RT thread | Always dispatched to main |
| Logging from DSP path | Prohibited |
| Restarting engine before Bluetooth is ready | Grace windows prevent this |
| Modifying shared state on background queues | Only main mutates |
| Installing taps on unstable devices | Delayed + retried installation |
| Crashes from `TooManyFramesToProcess` | Engine reconfigured safely |

---

## 10. Design Guidelines for New Features

When adding new logic:

### ✔ DO
- Keep DSP strictly real‑time safe  
- Perform network, disk, logging, or heavy computation on background queues  
- Touch engine/device state from main thread only  
- Respect Bluetooth warm‑up patterns  
- Use one‑way data flow:
```
RT → Processor → Manager → ViewModel → Views
```

### ✘ DO NOT
- Log or perform allocations inside the tap  
- Trigger start/stop/restart from non‑main queues  
- Modify shared state from CoreAudio threads  
- Attempt synchronous waits from RT threads  

---

## 11. Summary

AudioMonitorApp’s concurrency strategy provides:

- **Real‑time safe DSP**
- **Main‑thread controlled device lifecycle**
- **Resilient HAL error handling**
- **Stable Bluetooth transitions**
- **Clean SwiftUI interaction**

Following these patterns keeps the app responsive even during:
- rapid USB ↔ Bluetooth transitions  
- internal HAL reconfiguration  
- large bursts of log output  
- high‑frequency DSP workloads  

This enhanced document serves as the definitive concurrency reference for AudioMonitorApp.
