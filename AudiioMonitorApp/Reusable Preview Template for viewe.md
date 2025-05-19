##  Preview template for Views

"""
#Preview {
    // Create a dummy audio manager instance
    let dummyAudioManager = DummyAudioManager()
    dummyAudioManager.startMonitoring()

    // Create a log manager with the dummy audio manager
    let logManager = LogManager(audioManager: dummyAudioManager)

    // Create the view model using the dummy log manager
    let viewModel = AudioMonitorViewModel(logManager: logManager)

    // Inject into your view here
    return AudioMonitorView(viewModel: viewModel)
        .environmentObject(logManager) // optional, if your view expects it
}

"""

 replace AudioMonitorView(viewModel: viewModel) with whatever view you’re testing. For example:
	•	AudioStatsView(viewModel: viewModel)
	•	AdvancedLogViewerView(viewModel: viewModel)
	•	LogViewerView(viewModel: viewModel)
__Note__:
	•	The view has a matching init(viewModel:) initializer.
	•	The mock DummyAudioManager and LogManager conform to the required protocols.
