# `AudioProcessor.swift` Documentation

## Overview

The `AudioProcessor` is a `@MainActor`-isolated class responsible for processing real-time audio buffers and computing decibel (dBFS) levels for left and right channels. It also publishes audio statistics and optionally logs audio events.

## Key Features

- Computes RMS and converts it to decibel full scale (dBFS).
- Clamps dB values to a configurable floor threshold for UI stability.
- Publishes audio statistics using Combine.
- Isolated to `@MainActor` for UI-safe updates.
- Optionally sends events to a `LogManager`.

---

## Properties

```swift
private let dBFloorThreshold: Float = -20.0
```
Prevents display of meaningless values below -20 dBFS. Improves visual clarity in UI meters.

```swift
public private(set) var currentLeftLevel: Float = -80.0
public private(set) var currentRightLevel: Float = -80.0
```
Tracks the most recent left/right dB levels (clamped). Writable only within `AudioProcessor`.

```swift
public nonisolated let audioStatsStream = PassthroughSubject<AudioStats, Never>()
```
Publishes raw audio stats for downstream consumers (like diagnostics or logging).

```swift
private var logManager: LogManagerProtocol?
```
Optional reference to a log manager to forward audio event data.

---

## Methods

### `updateLogManager(_:)`
```swift
public func updateLogManager(_ logManager: LogManagerProtocol)
```
Assigns the logger for audio event logging.

---

### `process(buffer:inputName:inputID:)`
```swift
public func process(buffer: AVAudioPCMBuffer, inputName: String, inputID: Int)
```
Main audio processing method:
- Computes dBFS for left/right channels.
- Applies floor threshold.
- Updates `currentLeftLevel` and `currentRightLevel`.
- Publishes `AudioStats`.
- Logs audio if supported by `logManager`.

**Note**: Must be called from the main actor.

---

### `calculateRMS(samples:count:)`
```swift
private nonisolated func calculateRMS(samples: UnsafePointer<Float>, count: Int) -> Float
```
Computes the root mean square (RMS) of a float buffer, used in dBFS calculation.

---

### `format(_:precision:)`
```swift
public func format(_ value: Float, precision: Int = 1) -> String
```
Returns a formatted string for dB values, clamping non-finite values to `-80.0`.

---

## Concurrency Notes

- The class is fully `@MainActor`-isolated.
- Safe to use in Swift concurrency environments.
- External updates must use `Task { @MainActor in ... }`.
