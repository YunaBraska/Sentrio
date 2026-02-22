import Combine
import Foundation

final class RulesEngine {
    private let audio: AudioManager
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()

    init(audio: AudioManager, settings: AppSettings) {
        self.audio = audio
        self.settings = settings
        subscribe()
    }

    // MARK: – Subscriptions

    private func subscribe() {
        NotificationCenter.default
            .publisher(for: .audioDevicesChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.onDevicesChanged() }
            .store(in: &cancellables)

        settings.$outputPriority.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in if self?.settings.isAutoMode == true { self?.applyOutputRules() } }
            .store(in: &cancellables)

        settings.$inputPriority.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in if self?.settings.isAutoMode == true { self?.applyInputRules() } }
            .store(in: &cancellables)

        settings.$isAutoMode.dropFirst().filter { $0 }.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyRules() }
            .store(in: &cancellables)
    }

    // MARK: – Rules application

    private func onDevicesChanged() {
        for d in audio.outputDevices {
            settings.registerDevice(uid: d.uid, name: d.name, isOutput: true)
        }
        for d in audio.inputDevices {
            settings.registerDevice(uid: d.uid, name: d.name, isOutput: false)
        }
        guard settings.isAutoMode else { return }
        applyRules()
    }

    func applyRules() {
        applyOutputRules(); applyInputRules()
    }

    private func applyOutputRules() {
        apply(priority: settings.outputPriority,
              disabled: settings.disabledOutputDevices,
              connected: audio.outputDevices,
              current: audio.defaultOutput,
              isInput: false)
    }

    private func applyInputRules() {
        apply(priority: settings.inputPriority,
              disabled: settings.disabledInputDevices,
              connected: audio.inputDevices,
              current: audio.defaultInput,
              isInput: true)
    }

    private func apply(
        priority: [String],
        disabled: Set<String>,
        connected: [AudioDevice],
        current: AudioDevice?,
        isInput: Bool
    ) {
        let eligible = connected.filter { !disabled.contains($0.uid) }
        guard let target = RulesEngine.selectDevice(from: eligible, priority: priority) else { return }
        guard current?.uid != target.uid else { return }

        let isOutput = !isInput
        // Save outgoing device volumes
        if let current {
            if let vol = audio.volume(for: current, isOutput: isOutput) {
                settings.saveVolume(vol, for: current.uid, isOutput: isOutput)
            }
            if !isInput {
                settings.saveAlertVolume(AudioManager.readAlertVolume(), for: current.uid)
            }
        }

        audio.setDefault(target, isInput: isInput)

        // Restore incoming device volumes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            if let vol = settings.savedVolume(for: target.uid, isOutput: isOutput) {
                audio.setVolume(vol, for: target, isOutput: isOutput)
            }
            if !isInput, let alertVol = settings.savedAlertVolume(for: target.uid) {
                audio.setAlertVolume(alertVol)
            }
        }
    }

    // MARK: – Core selection logic (static for unit testing)

    static func selectDevice(from connected: [AudioDevice], priority: [String]) -> AudioDevice? {
        guard let uid = priority.first(where: { uid in connected.contains { $0.uid == uid } })
        else { return nil }
        return connected.first { $0.uid == uid }
    }

    // MARK: – Manual switch (from UI)

    func switchTo(_ device: AudioDevice, isInput: Bool) {
        let isOutput = !isInput
        let current = isInput ? audio.defaultInput : audio.defaultOutput
        if let current {
            if let vol = audio.volume(for: current, isOutput: isOutput) {
                settings.saveVolume(vol, for: current.uid, isOutput: isOutput)
            }
            if !isInput { settings.saveAlertVolume(AudioManager.readAlertVolume(), for: current.uid) }
        }
        audio.setDefault(device, isInput: isInput)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            if let vol = settings.savedVolume(for: device.uid, isOutput: isOutput) {
                audio.setVolume(vol, for: device, isOutput: isOutput)
            }
            if !isInput, let alertVol = settings.savedAlertVolume(for: device.uid) {
                audio.setAlertVolume(alertVol)
            }
        }
    }
}
