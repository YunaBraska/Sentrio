import Combine
import Foundation

final class RulesEngine {
    private let audio: AudioManager
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()

    private static let estimatedMillisSavedPerAutoSwitch = 2500
    private var recentAutoSwitchTimestamps: [Date] = []
    private var lastAutoSwitchAtByRole: [Bool: Date] = [:] // key: isInput

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
            .sink { [weak self] _ in
                guard let self else { return }
                if settings.isAutoMode { applyOutputRules() }
            }
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
            settings.registerDevice(
                uid: d.uid,
                name: d.name,
                isOutput: true,
                transportType: d.transportType,
                iconBaseName: d.iconBaseName,
                modelUID: d.modelUID,
                isAppleMade: d.isAppleMade,
                bluetoothMinorType: d.bluetoothMinorType
            )
        }
        for d in audio.inputDevices {
            settings.registerDevice(
                uid: d.uid,
                name: d.name,
                isOutput: false,
                transportType: d.transportType,
                iconBaseName: d.iconBaseName,
                modelUID: d.modelUID,
                isAppleMade: d.isAppleMade,
                bluetoothMinorType: d.bluetoothMinorType
            )
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

        recordAutoSwitch(isInput: isInput)

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
            let expectedVol = settings.savedVolume(for: target.uid, isOutput: isOutput)
            let expectedAlertVol = !isInput ? settings.savedAlertVolume(for: target.uid) : nil

            var didApplyAny = false
            if let vol = expectedVol {
                audio.setVolume(vol, for: target, isOutput: isOutput)
                didApplyAny = true
            }
            if let alertVol = expectedAlertVol {
                audio.setAlertVolume(alertVol)
                didApplyAny = true
            }

            guard didApplyAny else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self else { return }
                var ok = true
                if let expectedVol {
                    let actual = audio.volume(for: target, isOutput: isOutput) ?? expectedVol
                    if abs(actual - expectedVol) > 0.03 { ok = false }
                }
                if let expectedAlertVol {
                    let actualAlert = AudioManager.readAlertVolume()
                    if abs(actualAlert - expectedAlertVol) > 0.03 { ok = false }
                }
                if ok { settings.signalIntegrityScore += 5 }
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
        if let lastAuto = lastAutoSwitchAtByRole[isInput], Date().timeIntervalSince(lastAuto) <= 5 {
            settings.signalIntegrityScore -= 3
        }

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

    private func recordAutoSwitch(isInput: Bool) {
        settings.autoSwitchCount += 1
        settings.millisecondsSaved += Self.estimatedMillisSavedPerAutoSwitch
        settings.signalIntegrityScore += 10

        let now = Date()
        lastAutoSwitchAtByRole[isInput] = now

        recentAutoSwitchTimestamps.append(now)
        recentAutoSwitchTimestamps.removeAll { now.timeIntervalSince($0) > 20 }
        if recentAutoSwitchTimestamps.count == 3 {
            settings.signalIntegrityScore -= 10
        }
    }
}
