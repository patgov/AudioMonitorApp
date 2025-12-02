#AudioMonitorApp

📦 AudioMonitorApp — v1.3.0

Released: 2025-02-12

This release is the largest stability improvement to date, with deep fixes in CoreAudio integration, Bluetooth device handling, engine restarts, and device switching logic. AirPods and other Bluetooth microphones now switch cleanly, recover from failures gracefully, and produce stable readings without hanging the app.

✨ Added

Bluetooth & Device Handling

	•	Added Bluetooth pre-roll silence gating, preventing false silence readings during AirPods warm-up.
	•	Implemented first-frame audio detection to validate device readiness before measurement begins.
	•	Added automatic fallback to the previous working device when Bluetooth routes fail (“zombie device detection”).
	•	Added deferral window for system-default device changes so Bluetooth transitions don’t fire too early.
	•	Added grace-period auto-select window to avoid switching rapidly during device churn.

Audio Engine & HAL Interaction

	•	Added HAL -10877 backoff logic, preventing repeated engine restarts during CoreAudio device-not-ready states.
	•	Added engine quiescing during route changes to stabilize CoreAudio taps and prevent missing-node failures.
	•	Added detailed diagnostic logging for:
	•	device adoption events
	•	HAL recovery attempts
	•	routing changes
	•	audio probe summaries
	•	fallback decisions
	•	device validation issues

🛠️ Changed / Improved

Engine Lifecycle

	•	Significantly hardened startEngine() and stopEngine() sequencing.
	•	Removed race conditions causing redundant or early device restarts.
	•	Improved enforcement of “tap installed” semantics to avoid duplicate AVAudioNode taps.

Adaptive Noise Floor

	•	Reworked the noise floor learning to:
	•	delay learning until device is producing non-zero audio
	•	reset on device change
	•	ignore silence during Bluetooth warmup

Device Selection

	•	Unified the logic for user-pinned vs system-selected devices.
	•	Improved validation when switching between USB ↔ Bluetooth ↔ Built-In devices.
	•	Enabled cleaner adoption of new system-default microphones.

🐞 Fixed

	•	Fixed repeated AudioObjectSetPropertyData: no object with given ID errors during Bluetooth switching.
	•	Fixed device lockups caused by CoreAudio reporting devices before they are fully ready.
	•	Fixed crashes due to stale IOProc, phantom device IDs, and missing HAL shell objects.
	•	Fixed infinite loops where HAL -10877 errors cascaded into continuous restart attempts.
	•	Fixed cases where restored UserDefaults device failed to initialize on launch.
	•	Fixed out-of-order IOWorkLoop messages by tightening the engine-restart sequence.
	•	Fixed incorrect noise-floor baselines caused by early silence learning.

🧹 Maintenance

	•	Cleaned up legacy device-handling code and removed outdated logic paths.
	•	Improved documentation around:
	•	HAL error codes
	•	Bluetooth warmup timing
	•	CoreAudio routing behavior
	•	engine restart conditions
	•	Consistent naming and comments across AudioManager and supporting modules.

🚀 Summary

This release dramatically improves Bluetooth stability, engine reliability, and CoreAudio compatibility.
Switching between USB, Built-In, and  AirPods microphones is now:

✔ Smooth
✔ Fast
✔ Predictable
✔ Resilient to Apple’s HAL quirks

