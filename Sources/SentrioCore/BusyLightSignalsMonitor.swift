import AppKit
import Combine
import CoreAudio
import CoreMediaIO
import Foundation
import MediaPlayer

final class BusyLightSignalsMonitor: ObservableObject {
    @Published private(set) var signals = BusyLightSignals(
        microphoneInUse: false,
        cameraInUse: false,
        screenRecordingInUse: false,
        musicPlaying: false
    )

    private let microphone: BusyLightMicrophoneMonitor
    private let camera: BusyLightCameraMonitor
    private let screenRecording: BusyLightScreenRecordingMonitor
    private let playback: BusyLightPlaybackMonitor
    private var cancellables = Set<AnyCancellable>()

    init(audio: AudioManager) {
        microphone = BusyLightMicrophoneMonitor(audio: audio)
        camera = BusyLightCameraMonitor()
        screenRecording = BusyLightScreenRecordingMonitor()
        playback = BusyLightPlaybackMonitor(audio: audio)

        microphone.$isMicrophoneInUse
            .combineLatest(camera.$isCameraInUse, screenRecording.$isScreenRecordingInUse)
            .combineLatest(playback.$isPlaybackInUse)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] left, playback in
                let (mic, cam, screen) = left
                self?.signals = BusyLightSignals(
                    microphoneInUse: mic,
                    cameraInUse: cam,
                    screenRecordingInUse: screen,
                    musicPlaying: playback
                )
            }
            .store(in: &cancellables)
    }
}

// MARK: - Microphone

private final class BusyLightMicrophoneMonitor: ObservableObject {
    @Published private(set) var isMicrophoneInUse = false

    private let audio: AudioManager
    private var cancellables = Set<AnyCancellable>()
    private var listener: AudioListenerToken?

    init(audio: AudioManager) {
        self.audio = audio

        audio.$defaultInput
            .receive(on: DispatchQueue.main)
            .sink { [weak self] device in
                self?.installListener(for: device)
            }
            .store(in: &cancellables)

        installListener(for: audio.defaultInput)
    }

    deinit {
        removeListener()
    }

    private struct AudioListenerToken {
        let objectID: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private func installListener(for device: AudioDevice?) {
        removeListener()
        guard let device else {
            isMicrophoneInUse = false
            return
        }

        let objectID = AudioObjectID(device.id)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(device.id, &address) else {
            isMicrophoneInUse = false
            return
        }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh(deviceID: device.id) }
        }

        AudioObjectAddPropertyListenerBlock(objectID, &address, .main, block)
        listener = AudioListenerToken(objectID: objectID, address: address, block: block)
        refresh(deviceID: device.id)
    }

    private func removeListener() {
        guard var token = listener else { return }
        AudioObjectRemovePropertyListenerBlock(token.objectID, &token.address, .main, token.block)
        listener = nil
    }

    private func refresh(deviceID: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let ok = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &running) == noErr
        isMicrophoneInUse = ok && running != 0
    }
}

// MARK: - Camera

private final class BusyLightCameraMonitor: ObservableObject {
    @Published private(set) var isCameraInUse = false

    private var listenerBlocks: [CMIODeviceID: CMIOObjectPropertyListenerBlock] = [:]
    private var systemListener: CMIOObjectPropertyListenerBlock?
    private let systemObjectID = CMIOObjectID(kCMIOObjectSystemObject)

    init() {
        installSystemListener()
        rebuildDeviceListeners()
        refresh()
    }

    deinit {
        removeSystemListener()
        removeDeviceListeners()
    }

    private func installSystemListener() {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.rebuildDeviceListeners()
                self?.refresh()
            }
        }
        CMIOObjectAddPropertyListenerBlock(systemObjectID, &address, .main, block)
        systemListener = block
    }

    private func removeSystemListener() {
        guard let block = systemListener else { return }
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        CMIOObjectRemovePropertyListenerBlock(systemObjectID, &address, .main, block)
        systemListener = nil
    }

    private func rebuildDeviceListeners() {
        removeDeviceListeners()

        for deviceID in listDevices() {
            installDeviceListener(deviceID: deviceID)
        }
    }

    private func installDeviceListener(deviceID: CMIODeviceID) {
        let objectID = CMIOObjectID(deviceID)
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }

        let status = CMIOObjectAddPropertyListenerBlock(objectID, &address, .main, block)
        guard status == noErr else { return }
        listenerBlocks[deviceID] = block
    }

    private func removeDeviceListeners() {
        for (deviceID, block) in listenerBlocks {
            let objectID = CMIOObjectID(deviceID)
            var address = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            CMIOObjectRemovePropertyListenerBlock(objectID, &address, .main, block)
        }
        listenerBlocks.removeAll()
    }

    private func refresh() {
        isCameraInUse = listDevices().contains(where: { isDeviceRunningSomewhere(deviceID: $0) })
    }

    private func listDevices() -> [CMIODeviceID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(systemObjectID, &address, 0, nil, &dataSize) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<CMIODeviceID>.size
        guard count > 0 else { return [] }

        var devices = Array(repeating: CMIODeviceID(), count: count)
        var used: UInt32 = 0
        let status = devices.withUnsafeMutableBytes { buf in
            CMIOObjectGetPropertyData(systemObjectID, &address, 0, nil, dataSize, &used, buf.baseAddress)
        }
        guard status == noErr else { return [] }
        return devices
    }

    private func isDeviceRunningSomewhere(deviceID: CMIODeviceID) -> Bool {
        let objectID = CMIOObjectID(deviceID)
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var running: UInt32 = 0
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        let status = CMIOObjectGetPropertyData(objectID, &address, 0, nil, size, &used, &running)
        return status == noErr && running != 0
    }
}

// MARK: - Playback (default output activity)

private final class BusyLightPlaybackMonitor: ObservableObject {
    @Published private(set) var isPlaybackInUse = false

    private var timer: Timer?
    private var consecutiveActiveSamples = 0
    private var consecutiveInactiveSamples = 0

    private static let activationSamplesRequired = 2
    private static let deactivationSamplesRequired = 3
    private static let ignoredOutputBundleIDs: Set<String> = [
        "com.apple.WebKit.GPU",
        "com.apple.WebKit.WebContent",
    ]

    init(audio _: AudioManager) {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer?.tolerance = 0.2
    }

    deinit {
        timer?.invalidate()
    }

    private func refresh() {
        if hasNowPlayingSignal() {
            consecutiveActiveSamples = Self.activationSamplesRequired
            consecutiveInactiveSamples = 0
            if !isPlaybackInUse { isPlaybackInUse = true }
            return
        }

        let processActivity = hasActiveAudioOutputProcess()
        if processActivity {
            consecutiveActiveSamples += 1
            consecutiveInactiveSamples = 0
            if !isPlaybackInUse, consecutiveActiveSamples >= Self.activationSamplesRequired {
                isPlaybackInUse = true
            }
            return
        }

        consecutiveInactiveSamples += 1
        consecutiveActiveSamples = 0
        if isPlaybackInUse, consecutiveInactiveSamples >= Self.deactivationSamplesRequired {
            isPlaybackInUse = false
        }
    }

    private func hasNowPlayingSignal() -> Bool {
        let nowPlaying = MPNowPlayingInfoCenter.default()
        if nowPlaying.playbackState == .playing { return true }

        guard let info = nowPlaying.nowPlayingInfo else { return false }
        if let rate = info[MPNowPlayingInfoPropertyPlaybackRate] as? Double { return rate > 0.01 }
        if let rate = info[MPNowPlayingInfoPropertyPlaybackRate] as? Float { return rate > 0.01 }
        if let rate = info[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber { return rate.doubleValue > 0.01 }
        return false
    }

    private func hasActiveAudioOutputProcess() -> Bool {
        let ownPID = Int32(ProcessInfo.processInfo.processIdentifier)

        for processObjectID in processObjectIDs() {
            guard let outputRunning = uint32Property(
                objectID: processObjectID,
                selector: kAudioProcessPropertyIsRunningOutput
            ), outputRunning != 0 else { continue }

            guard let ioRunning = uint32Property(
                objectID: processObjectID,
                selector: kAudioProcessPropertyIsRunning
            ), ioRunning != 0 else { continue }

            guard let pid = int32Property(
                objectID: processObjectID,
                selector: kAudioProcessPropertyPID
            ), pid != ownPID else { continue }

            let bundleID = stringProperty(
                objectID: processObjectID,
                selector: kAudioProcessPropertyBundleID
            )
            if let bundleID, Self.ignoredOutputBundleIDs.contains(bundleID) {
                continue
            }
            return true
        }
        return false
    }

    private func processObjectIDs() -> [AudioObjectID] {
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObjectID, &address, 0, nil, &dataSize) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var processIDs = Array(repeating: AudioObjectID(), count: count)
        var usedSize = dataSize
        let status = processIDs.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let baseAddress = buffer.baseAddress else { return -1 }
            return AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &usedSize, baseAddress)
        }
        guard status == noErr else { return [] }
        return processIDs
    }

    private func uint32Property(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value
    }

    private func int32Property(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> Int32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Int32 = 0
        var size = UInt32(MemoryLayout<Int32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value
    }

    private func stringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, ptr)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

// MARK: - Screen recording (best-effort)

private final class BusyLightScreenRecordingMonitor: ObservableObject {
    @Published private(set) var isScreenRecordingInUse = false

    private var observers: [NSObjectProtocol] = []

    init() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        })
        observers.append(nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        })
        refresh()
    }

    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        for o in observers {
            nc.removeObserver(o)
        }
    }

    private func refresh() {
        isScreenRecordingInUse = NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == "com.apple.screencaptureui"
        }
    }
}
