# BluetoothHandling.md  
### Robust Bluetooth Input Management in AudioMonitorApp

AudioMonitorApp implements a carefully engineered Bluetooth-aware input pipeline designed to compensate for the quirks of AirPods, Beats, and other HFP/HSP-style devices.  
These devices frequently introduce:

- Route-change delays  
- Zero-frames / silent warm-up periods  
- HAL plugin inconsistencies (`!obj`, `!dev`)  
- Fluctuating channel layout and sample rate  
- Temporary device ID churn  

This document explains how the app handles these cases safely and predictably.

---

## 1. Why Bluetooth Devices Are Special

Bluetooth microphones operate under different constraints than wired USB or built-in mics.  
Particularly:

| Issue | Explanation |
|------|-------------|
| **Warm-Up Silence (0.0 samples)** | AirPods produce ~150–600 ms of pure zero during route activation. |
| **ID Swap / Reconnect** | macOS will create temporary CoreAudio object IDs when reconnecting. |
| **Slow Default-Device Announcement** | System default input changes fire *before* the device is fully ready. |
| **Async Route Activation** | I/O is not available until the BT stack completes SCO/HFP negotiation. |

These must be handled safely to avoid broken VU meters, false silence warnings, or crashes during tap installation.

---

## 2. Deferring Adoption of Bluetooth Inputs

When the system default changes to a Bluetooth device:

- The app **does NOT immediately switch.**
- Instead, it marks:

```
pendingSystemDefaultInput = def
lastSystemInputChangeAt = Date()
inputAutoSelectGraceUntil = now + bluetoothAdoptionDelay  // ~200–600 ms
```

The adoption happens only when:

- The device list stabilizes  
- No additional system default changes occur  
- Grace window has elapsed  

This prevents oscillation when the OS rapidly reports intermediate device states.

---

## 3. Engine Quiescing for Route Changes

Before switching into a Bluetooth input, the app:

1. **Stops the engine**
2. **Removes any existing tap**
3. **Resets internal state flags**
4. **Delays restart slightly**  
   (Bluetooth I/O is not ready instantly—waiting prevents render errors)

This avoids:

- CoreAudio “out of order message” warnings  
- HAL IOProc destruction errors  
- -10877 render callback faults  

---

## 4. Noise-Floor Hold at –120 dB Until BT Is Ready

Until stable, non-zero audio frames arrive, the app:

- Reports **–120 dBFS** (true digital silence)
- Zeroes out peak-tracking
- Prevents accidental noise-floor learning

This avoids:

- Sudden fake spikes  
- “Half-initialized” frame artifacts  
- The meter bouncing during warm-up  

The app considers Bluetooth “warm-up complete” when:

```
peakNonZero == true for (2–3 consecutive frames)
```

---

## 5. Digital Silence Fallback Protection

If a Bluetooth microphone continues producing **total silence** after warm-up:

The logic triggers:

```
if bluetoothInputSilentFor > N frames
    fallbackToLastReliableInput()
```

This prevents:

- The app getting stuck on a dead AirPods route
- Frozen VU meters
- Misleading readings

Fallback target is usually:

- Built-in mic  
- Previously user-selected device  
- Or system default (non-BT)

---

## 6. Recovery From HAL Errors

The following HAL errors are common during Bluetooth route changes:

| Error | Meaning |
|-------|---------|
| `!obj` | CoreAudio deleted the temporary proxy before we queried it |
| `!dev` | Device vanished mid-IOProc teardown |
| `-10877` | Render callback failed |
| `TooManyFramesToProcess` | BT stack didn’t deliver the requested frame count |

The app recovers by:

- Restarting the engine cleanly  
- Re-installing taps only *after* stabilization  
- Re-fetching device info  
- Reapplying user-pinned selection if applicable  

---

## 7. Event Logging for Bluetooth Transitions

The log viewer records:

- System default input notifications  
- Deferred BT adoption  
- Warm-up timers  
- Silence fallback  
- Tap installation/removal  
- Engine restarts  
- HAL error bursts  

This makes Bluetooth-related issues debuggable in the field.

---

## 8. Summary

Bluetooth audio input on macOS is inherently unstable during the first second of activation.  
AudioMonitorApp solves this through:

- Deferred adoption  
- Grace windows  
- Engine quiescing  
- Tap reinstall strategies  
- Noise-floor suppression  
- Silence fallback  
- Rich logging

The end result:  
**AirPods and Beats work reliably**, without broken meters, HAL crashes, or device lockups.

---

