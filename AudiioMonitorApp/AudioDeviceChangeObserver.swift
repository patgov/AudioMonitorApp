import Foundation
import CoreAudio

final class AudioDeviceChangeObserver: ObservableObject {
    @Published var availableInputDevices: [String] = []

    private var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    init() {
        refreshDeviceList()

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.refreshDeviceList()
        }
    }

    deinit {
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            {_,_ in }
        )
    }

    private func refreshDeviceList() {
        availableInputDevices = CoreAudioInputDeviceManager.getAllInputDeviceNames()
    }
}
