# Architecture

AudioMonitorApp – High‑Level Architecture
========================================

AudioMonitorApp is a real‑time **input‑side audio diagnostic tool** built on a modern SwiftUI + MVVM stack, with a CoreAudio‑backed audio core and structured logging.

At a high level there are four layers:

1. **UI Layer (SwiftUI)**
2. **ViewModel Layer (MVVM)**
3. **Audio Core Layer (AVAudioEngine + CoreAudio/HAL)**
4. **Logging & Diagnostics Layer**

This document explains how those pieces fit together and how audio data and state flow through the system.


## 1. Layered Overview

### 1.1 UI Layer (SwiftUI)

Main views:

- `AudioMonitorView`
  - Primary screen: device picker, stereo VU meters, numeric dBFS readout and status indicators.
  - Binds to `AudioMonitorViewModel` via `@StateObject` / `@ObservedObject`.
- `AudioStatsView`
  - Shows current numeric levels and basic statistics.
- `AdvancedLogViewerView`
  - In‑app log console with filters and search (developer‑facing).
- `AudioMonitorApp`
  - App entry point, wires the root view model into the SwiftUI scene.

The UI layer is **stateless** with respect to audio I/O: all device management, engine lifecycle, and measurements are delegated to the ViewModel + audio core.


### 1.2 ViewModel Layer (MVVM)

The central view model is:

- `AudioMonitorViewModel`
  - Owns a single `AudioManager` instance.
  - Exposes published properties representing:
    - Current device list.
    - Selected input device.
    - Current L/R VU levels, peaks and overmodulation flags.
    - Connection / engine status.
    - High‑level error flags and human‑readable status strings.
  - Coordinates:
    - Starting and stopping monitoring.
    - Selecting / pinning devices.
    - Opening the log viewer or diagnostics features.
    - Simple routing of `LogManager` messages into UI‑friendly form if needed.

The ViewModel should **not** perform low‑level audio work. It is the orchestration layer between the UI and the lower‑level audio core + logging system.


### 1.3 Audio Core Layer

The audio core has two primary components:

- `AudioManager`
  - Controls `AVAudioEngine` and its input node.
  - Manages device selection and CoreAudio notifications.
  - Installs / removes the input node tap.
  - Handles Bluetooth route changes, warm‑up, and HAL error recovery.
  - Maintains additional state such as:
    - `selectedDevice`
    - `userPinnedSelection`
    - `tapInstalled`
    - `isStarting`
    - `pendingSystemDefaultInput`
    - `inputAutoSelectGraceUntil`
- `AudioProcessor`
  - Pure processing of audio buffers.
  - Computes:
    - Left/right dBFS values.
    - Smoothed levels (fast‑attack / slow‑release).
    - Noise‑floor learning state.
    - Silence / activity detection.
  - Returns a lightweight `AudioStats` struct with the processed results.

`AudioManager` is responsible for:
- Acquiring audio buffers from CoreAudio.
- Feeding those buffers to `AudioProcessor`.
- Publishing processed stats to the ViewModel.

`AudioProcessor` is **deliberately stateless with respect to devices** – all routing and device identity logic lives in `AudioManager`.


### 1.4 Logging & Diagnostics Layer

- `LogManager`
  - Receives log events from `AudioManager`, `AudioProcessor`, and the ViewModel.
  - Stores logs in memory (and optionally on disk).
  - Exposes a stream suitable for binding to `AdvancedLogViewerView`.
- `LogWriter`
  - Responsible for the actual persistence and formatting of logs (e.g. to file for later analysis).

Diagnostic logging is a first‑class concern. Many CoreAudio and HAL issues are subtle and time‑based, so the app logs:

- All device list fetches.
- System default input changes.
- Tap installations/removals.
- Engine start/stop attempts and failures.
- HAL error codes (`!obj`, `!dev`, `-10877`, `TooManyFramesToProcess`).
- Bluetooth warm‑up, deferral windows, and fallbacks.


## 2. Data Flow

### 2.1 Real‑Time Audio Path

1. **CoreAudio / AVAudioEngine**
   - The `AVAudioEngine` input node is tapped.
   - On each render callback, an `AVAudioPCMBuffer` is delivered.

2. **AudioManager**
   - Receives the buffer in the tap closure.
   - Performs basic route checks (e.g. ensure selected device still valid).
   - Forwards the buffer to `AudioProcessor`.

3. **AudioProcessor**
   - Computes dBFS per channel.
   - Applies envelope/smoothing.
   - Updates noise‑floor learning.
   - Produces an `AudioStats` value.

4. **AudioMonitorViewModel**
   - Receives updated `AudioStats` from `AudioManager` (via Combine publishers or callbacks).
   - Updates `@Published` properties.

5. **SwiftUI Views**
   - `AudioMonitorView` and `AudioStatsView` react to changes via SwiftUI’s diffing.
   - `AnalogVUMeterView` (or equivalent) animates its needle/bar to the new levels.


### 2.2 Device and Route Changes

1. **System change**
   - macOS (or iPadOS) changes the default input (e.g. AirPods connect, USB interface unplugged).
   - A `AudioObjectPropertyListenerBlock` in `AudioManager` receives the notification.

2. **Decision logic**
   - If **user‑pinned** device exists:
     - External changes are either ignored or reverted.
   - If Bluetooth becomes default:
     - `AudioManager` defers adoption for a configurable warm‑up window.
     - Engine is temporarily quiesced (tap removed, engine stopped if necessary).
   - If a non‑Bluetooth default appears and no pinned device:
     - `AudioManager` automatically adopts it and restarts the engine.

3. **Recovery**
   - After warm‑up / grace periods:
     - Engine restarts with the new device.
     - Tap is re‑installed on the input node.
     - Noise‑floor learning is reset for the new route.

4. **Propagation**
   - Updated `selectedDevice` and `AudioStats` flow up through the ViewModel to the UI.
   - Log events are recorded, creating a timeline of what happened and why.


## 3. State & Error Handling

### 3.1 Engine Lifecycle

`AudioManager` maintains narrow, explicit flags:

- `isStarting` – prevents re‑entrant start attempts.
- `tapInstalled` – ensures the tap is only added once and removed correctly.
- `pendingTapRetry`, `tapRetryCount` – support controlled retries on failure.
- `forceSystemDefaultToSelected` (macOS only) – when true, external changes are reverted so that system default follows the app’s pinned selection.

On start:

1. Verify microphone permission.
2. Validate selected device.
3. Configure engine I/O format if necessary.
4. Install tap.
5. Start the engine, with retries if CoreAudio/HAL reports transient errors.

On stop:

1. Remove tap (if installed).
2. Stop engine.
3. Clear transient state used for retries/recovery.


### 3.2 Error Handling Philosophy

The app favors **graceful degradation** over crashes:

- If a Bluetooth input turns “digitally silent” for many consecutive frames, the app may:
  - Log the condition, and
  - Fallback to a more stable device (e.g. iPhone microphone or built‑in input).
- HAL errors are logged with their numeric codes and original messages.
- Engine restarts are throttled through grace windows and retry limits.
- Device selection is validated on each restart to avoid binding to stale device IDs.


## 4. Bluetooth and CoreAudio/HAL Integration

Bluetooth devices (AirPods, Beats, etc.) are **special‑case** participants in the architecture:

- They typically:
  - Appear and disappear more often.
  - Require warm‑up after connection before delivering stable audio.
  - Trigger more HAL errors when routes flap.

Architectural choices to handle this:

- **Deferral windows**
  - System default changes to Bluetooth are *not* adopted immediately.
  - `AudioManager` stores a `pendingSystemDefaultInput` and only adopts it after a warm‑up delay, during which engine may be quiesced.

- **Noise‑floor hold**
  - `AudioProcessor` can hold output at –120 dBFS until it sees a stable, non‑zero buffer, avoiding fake spikes during warm‑up.

- **Fallback path**
  - If a Bluetooth input stays silent (e.g., 60–90 consecutive frames at –120 dBFS), the app can automatically:
    - Log a “Bluetooth silence fallback” event.
    - Switch to a more stable wired or Continuity device.
    - Restart the engine with the fallback device.


## 5. Extensibility

The architecture is designed so that you can extend features without rewiring the entire app.

### 5.1 Add a New View or Widget

- Create a new SwiftUI view (e.g., `HistoryView`, `MiniWidgetView`).
- Inject or observe `AudioMonitorViewModel`.
- Bind to the same `@Published` properties the main view uses.
- The audio core remains unchanged.

### 5.2 Add New Audio Metrics

- Extend `AudioProcessor` to compute new metrics:
  - RMS (slow), LUFS, crest factor, etc.
- Add fields to `AudioStats`.
- Mirror new values in `AudioMonitorViewModel`.
- Display them in the appropriate view.

CoreAudio routing and engine control continue to live inside `AudioManager`.


### 5.3 Swap Logging Backend

- If you want structured logging (JSON, OSLog, etc.):
  - Implement a different `LogWriter`.
  - Keep `LogManager`’s public interface intact so the rest of the app doesn’t change.


## 6. File Map

At a high level, the architecture is reflected in these files:

- **UI**
  - `AudioMonitorView.swift`
  - `AdvancedLogViewerView.swift`
  - `AudioStatsView.swift`
  - `AudioMonitorApp.swift`

- **ViewModel**
  - `AudioMonitorViewModel.swift`

- **Audio Core**
  - `AudioManager.swift`
  - `AudioProcessor.swift`
  - `AudioDeviceInfo` / `AudioStats` models

- **Logging & Diagnostics**
  - `LogManager.swift`
  - `LogWriter.swift`

This separation keeps real‑time audio, UI rendering, and diagnostics clearly isolated, while still allowing them to work together with minimal glue code.


