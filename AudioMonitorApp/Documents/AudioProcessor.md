# AudioProcessor

AudioProcessor – Real-Time DSP, Level Computation & Noise-Floor Logic
=====================================================================

`AudioProcessor` handles all real-time analysis of incoming audio.  
It converts `AVAudioPCMBuffer` frames into clean, stable, visually accurate  
VU meter values and publishes structured `AudioStats`.

Its DSP routines are intentionally lightweight so they can run reliably  
inside the input tap callback at audio-frame granularity.

---

# 1. Responsibilities Overview

The AudioProcessor performs:

### ✔ dBFS Level Calculation  
- Per-channel peak amplitude  
- RMS or smoothed VU-style amplitude  
- Fast-attack / slow-release envelope behavior  

### ✔ Noise Floor & Silence Handling  
- Startup noise-floor smoothing  
- Initial meter lock at `−120 dBFS`  
- First-valid-frame detection  
- Long-term silence detection (for Bluetooth fallback)

### ✔ Meter Behavior & Smoothing  
- Prevents jitter using exponential decay filters  
- Simulates analog needle response curves  
- Avoids sudden jumps after route changes  

### ✔ Edge Case Detection  
- Digital silence frames  
- Non-zero peaks  
- Overmodulation / clipping  
- Invalid / zeroed buffers (common during Bluetooth warm-up)

### ✔ Publishing Results  
Outputs one struct per frame:

```swift
struct AudioStats {
    let leftDBFS: Float
    let rightDBFS: Float
    let peakNonZero: Bool
}
```

---

# 2. Processing Pipeline

When AudioManager receives each buffer from the input tap, it calls:

```
processor.process(buffer: buffer, at: time)
```

The DSP pipeline performs the following steps:

## 2.1 Channel Extraction  
AudioProcessor reads raw audio samples from the PCM buffer and ensures:

- Sample format is float32  
- Channel count matches expected configuration (1 or 2)  
- Out-of-spec buffers are rejected safely  

## 2.2 Peak Amplitude Detection  
The processor scans samples to calculate instantaneous peaks:

```swift
max(abs(sample))
```

This peak is converted to dBFS:

```swift
db = 20 * log10(peak)
```

Clamped to valid range:

- Minimum: −120 dBFS  
- Maximum: 0 dBFS  

## 2.3 Fast-Attack / Slow-Release Model  
To prevent flutter in the VU meter:

- Attack multiplier: ~0.4–0.6  
- Release multiplier: ~0.92–0.97  

This produces a behavior similar to:

- Vintage analog meters  
- Broadcast VU meters  
- Tape-era smoothing curves  

Attack is applied when signal increases, release when it decreases.

## 2.4 True Peak Detection  
A flag (`peakNonZero`) is set when a sample exceeds the noise floor.

This triggers:

- First-valid-frame events  
- Warm-up completion notification  
- Silence reset logic  

---

# 3. Noise Floor Learning

AudioProcessor uses a **learning phase** during device startup:

### Why?
Bluetooth devices produce invalid frames for 200–500 ms after connection.

### Behavior
1. Force output to **−120 dBFS** during the warm-up phase  
2. Wait until the first non-zero valid frame  
3. Once detected, release the freeze and smoothly fade into real values  

This prevents:
- Jumpy meters  
- False clipping warnings  
- Garbage data during Bluetooth activation  

---

# 4. Silence Detection & Bluetooth Fallback

If the processor receives **only digital silence** for too long:

Criteria:
- ~60–90 frames (0.5–1.2 seconds)
- `peakNonZero == false`
- Input device is Bluetooth

AudioManager receives a notification:

```
processorDelegate.didDetectExtendedSilence()
```

AudioManager then:
- Logs the event  
- Falls back to next-best device (USB mic or internal mic)  

This fixes a known CoreAudio issue:
> AirPods sometimes "connect" but do not start sending audio data.

---

# 5. Overmodulation & Clip Handling

Clipping occurs when:
- Peak approaches 0.0  
- dBFS ≥ −1.0  

AudioProcessor flags this instantly.

The UI then:
- Highlights in red  
- Shows a clip warning  
- Allows for later export or logging  

---

# 6. Error-Tolerant Design

AudioProcessor is designed to avoid throwing exceptions inside the tap
callback. It avoids:

- Memory allocations  
- Dynamic dispatch  
- Locks  
- Exceptions  

All logic is branch-light and deterministic.

In failure cases (rare), the processor returns:

```
AudioStats(left: -120, right: -120, peakNonZero: false)
```

Guaranteeing that:
- The UI will not crash
- The system will not deadlock
- The meters remain stable

---

# 7. Threading Considerations

AudioProcessor always runs on:

- The **real-time audio render thread** (tap callback)

Therefore:

- No locks  
- No async calls inside DSP  
- No writes to shared state  
- No heavy computation  

The ViewModel receives stats on the main actor after smoothing.

---

# 8. Responsibilities Summary

| Area | Role |
|------|------|
| Level Calculation | Convert raw samples → stable dBFS |
| Meter Smoothing | Fast attack / slow release behavior |
| Warm-Up Logic | Lock output at −120 dBFS until stable |
| Silence Detection | Detect Bluetooth failure cases |
| Stats Publishing | Provide clean values every frame |
| Real-Time Safety | Avoid heavy operations, remain deterministic |

---

# 9. Future Enhancements

Potential improvements:

- LUFS / EBU R128 loudness metering  
- RMS slow meter mode  
- Switchable analog meter models (BBC, DIN, VU)  
- Adjustable smoothing parameters  
- Noise gate for low-volume environments  

---

# 10. Summary

AudioProcessor is the DSP core of AudioMonitorApp.  
It provides clean, stable, accurate meter data while handling Bluetooth
warm-up issues, silence detection, and smoothing that mimics analog meters.

It is intentionally lightweight, real-time safe, and integrates cleanly with
AudioManager and the ViewModel.
