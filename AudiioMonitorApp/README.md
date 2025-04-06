#  AudioMonitorApp

	•	AudioManager.swift (handles input device selection and audio callback)
	•	AudioMonitorView.swift (main SwiftUI UI with VU meter and stats)
	•	LogWriter.swift (logs events to a file)
	•	AdvancedLogViewerView.swift (displays logs in the UI)
	•	App entry point (e.g. AudioMonitorApp.swift)

AudioProcessor.swift
Changes

• real-time dB level processing,
• smoothing,
• stereo channel support,
• silence/overmodulation detection,
• logging


