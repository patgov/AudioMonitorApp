# VUMeterBehavior.md  
### Analog-Style Meter Response, dBFS Calculation, Smoothing, and Visual Logic

This document defines how the VU meters in **AudioMonitorApp** behave, how audio levels are computed and smoothed, and the rules behind animation, clipping, and silence detection.

The goal is to match the feel of classic studio hardware (1970s VU meters) while maintaining modern digital precision (dBFS, peak detection, noise-floor compensation).

---

## 1. Signal Source

The VU meter receives its data from `AudioProcessor.swift`, which outputs:

- `leftDBFS: Double`
- `rightDBFS: Double`
- `peakNonZero: Bool`
- `noiseFloorLearned: Double`
- `instantPeak: Double`

Meter behavior is fully deterministic based on these inputs.

---

## 2. dBFS to Needle Mapping

The app uses **digital full-scale units**:

- `0 dBFS` = clipping  
- `-6 dBFS` to `-18 dBFS` = typical speech  
- `-24 dBFS` to `-60 dBFS` = quiet environment  
- `-120 dBFS` = absolute digital silence  

The meter visually maps this using a **logarithmic arc**:

```
visualValue = remap(logAmplitude)
```

This ensures:

- Smooth travel near the bottom  
- Precise, fast action near peaks  
- True-to-hardware non-linear aesthetic  

---

## 3. Attack and Release Times

The analog meter behavior includes smoothing:

### **Attack (rise)**
- Fast (≈ 5–10 ms)
- Follows sudden loud events quickly
- Avoids "laggy" needle effect

### **Release (fall)**
- Slow (≈ 300 ms)
- Matches VU hardware where needles fall gently
- Produces readable, pleasant movement

A simple envelope follower:

```
if newValue > displayedValue:
    displayedValue += attackRate
else:
    displayedValue -= releaseRate
```

---

## 4. Overmodulation / Clipping Detection

If a channel exceeds:

```
>= -1.0 dBFS
```

…then:

- Meter arc turns red  
- Clip indicator appears  
- A short **hold time** prevents flickering

Hold is approximately:

```
clipHoldTime = 200 ms
```

Clipping is logged if persistent.

---

## 5. Silence Detection

If audio remains at:

```
<= -110 dBFS for N consecutive frames
```

And `noiseFloorLearned > -110 dBFS` (device fully initialized), then:

- Silence indicator displays  
- Meter needle rests smoothly at minimum  
- No jitter (because Bluetooth warms up with zeros)  

This avoids false warnings during BT warm-up.

---

## 6. Noise Floor Learning Integration

AudioProcessor computes a dynamic noise floor:

- Learned gradually over ~250–500 ms
- Stops adapting while signal is present
- Uses it for meter **baseline suppression**

If noise floor rises (e.g., due to fan hum):

- Meter begins at the true device self-noise  
- Prevents small fluctuations from showing as "signal"

---

## 7. Zero-Crossing Peak Detection

To detect speech vs. artifacts, AudioProcessor tracks zero-crossings:

- Helps confirm that a non-zero sample is “real audio”  
- Reduces false positives during Bluetooth warm-up  
- Informs silence/hot-signal warnings  

---

## 8. Visual Rendering Rules

The SwiftUI view (AnalogVUMeterView):

- Uses a pre-rendered arc with tick marks  
- Needle rotates using angle mapping:  
  - -18° = silence  
  - +34° = 0 dBFS  
- Smooth interpolation with `withAnimation(.easeOut(duration: 0.1))`

Clipping color:

- Default arc color = green  
- High-mezzo = yellow  
- Hot = orange  
- Clipping = red  

---

## 9. Stereo Handling

Meters operate independently:

- Separate attack/release envelopes  
- Separate clipping states  
- Independent silence detection  
- Shared timebase for animation efficiency  

---

## 10. Summary

AudioMonitorApp’s VU meters reproduce professional studio behavior:

- Analog motion  
- Realistic inertia  
- Accurate dBFS calculation  
- Zero-crossing peak validation  
- Smooth transitions  
- True stereo independence  
- Graceful handling of Bluetooth warm-up  

This produces a visually pleasing, reliable meter suitable for engineers, musicians, and diagnostics.

---

