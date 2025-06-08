# AudioMonitorApp Structure

This document outlines the structure and components of the AudioMonitorApp, organized using the MVVM (Model-View-ViewModel) design pattern. Each section describes the relevant files, classes, protocols, and SwiftUI views grouped by folder.

---

## Folder Layout

- `Model/`: Data models, statistics, log entries
- `ViewModel/`: Binds audio processing and logs to the user interface
- `View/`: SwiftUI views and visual components
- `Audio/`: Real-time audio processing and CoreAudio management
- `Logging/`: Audio event detection, log writing, diagnostics
- `Widget/`: Widget extension and timeline handling
- `Preview/`: Preview-safe components and test data

---

## View

### `StyledAnalogVUMeterView.swift`
- **Purpose**: Renders a horizontal analog-style VU meter with a 1950s aesthetic.
- **Visual Layers**:
  - Color-coded arc segments (safe, warning, red zones)
  - FCC-style dB ticks from -20 to +7
  - Numbered scale
  - Animated needle indicating current dB level
  - Glass overlay effect
- **Inputs**:
  - `level: Double`: Normalized dB level input (0.0 to 1.0)
  - `showClipping: Bool`: Optional visual indicator for overmodulation
- **Closures/Computed Properties**:
  - `clampedAngle`: Computes needle angle from dB input using calibration and angle bounds
  - `needleTip`: Calculates needle tip coordinates from angle
- **Dependencies**:
  - `AnalogVUMeterArcSegments`, `AnalogVUMeterTicks`, `AnalogVUNumbers`, `AnalogVUNeedle`, `VUMeterGlassOverlay`

---

*(Additional files and architecture will be documented as development continues.)*

