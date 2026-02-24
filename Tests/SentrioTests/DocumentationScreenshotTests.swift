import AppKit
import CoreAudio
import Foundation
@testable import SentrioCore
import SwiftUI
import XCTest

@MainActor
final class DocumentationScreenshotTests: XCTestCase {
    private static let generationFlag = "SENTRIO_GENERATE_SCREENSHOTS"
    private static let outputPathKey = "SENTRIO_SCREENSHOT_DIR"

    private var previousLocalizationOverride: String?
    private var screenshotFixture: DocumentationScreenshotFixture?

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        guard ProcessInfo.processInfo.environment[Self.generationFlag] == "1" else {
            throw XCTSkip(
                "Set \(Self.generationFlag)=1 to generate screenshots."
            )
        }

        previousLocalizationOverride = L10n.overrideLocalization
        L10n.overrideLocalization = "en"
        screenshotFixture = DocumentationScreenshotFixture()
    }

    override func tearDownWithError() throws {
        screenshotFixture?.shutdown()
        screenshotFixture = nil
        L10n.overrideLocalization = previousLocalizationOverride
        previousLocalizationOverride = nil
        try super.tearDownWithError()
    }

    func test_generateDocumentationScreenshots() throws {
        guard let screenshotFixture else {
            XCTFail("Fixture should be available in screenshot mode.")
            return
        }

        let outputDirectory = try outputDirectoryURL()
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let menuBarURL = outputDirectory.appendingPathComponent("bar_menu.png")
        let preferencesOutputURL = outputDirectory.appendingPathComponent("preferences_output.png")
        let preferencesInputURL = outputDirectory.appendingPathComponent("preferences_input.png")
        let preferencesBusyLightURL = outputDirectory.appendingPathComponent("preferences_busy_light.png")
        let preferencesGeneralURL = outputDirectory.appendingPathComponent("preferences_general.png")
        let legacyPreferencesURL = outputDirectory.appendingPathComponent("preferences.png")

        try ScreenshotRenderer.render(
            MenuBarView()
                .environmentObject(screenshotFixture.settings)
                .environmentObject(screenshotFixture.audio)
                .environmentObject(screenshotFixture.appState),
            size: NSSize(width: 340, height: 600),
            to: menuBarURL
        )

        try ScreenshotRenderer.render(
            PreferencesView(renderMode: .screenshot, initialTab: .output)
                .environmentObject(screenshotFixture.settings)
                .environmentObject(screenshotFixture.audio)
                .environmentObject(screenshotFixture.busyLight)
                .environmentObject(screenshotFixture.appState),
            size: NSSize(width: 540, height: 680),
            to: preferencesOutputURL
        )

        try ScreenshotRenderer.render(
            PreferencesView(renderMode: .screenshot, initialTab: .input)
                .environmentObject(screenshotFixture.settings)
                .environmentObject(screenshotFixture.audio)
                .environmentObject(screenshotFixture.busyLight)
                .environmentObject(screenshotFixture.appState),
            size: NSSize(width: 540, height: 680),
            to: preferencesInputURL
        )

        screenshotFixture.primeBusyLightSnapshot()
        XCTAssertFalse(screenshotFixture.busyLight.connectedDevices.isEmpty)
        try ScreenshotRenderer.render(
            PreferencesView(renderMode: .screenshot, initialTab: .busyLight)
                .environmentObject(screenshotFixture.settings)
                .environmentObject(screenshotFixture.audio)
                .environmentObject(screenshotFixture.busyLight)
                .environmentObject(screenshotFixture.appState),
            size: NSSize(width: 540, height: 680),
            to: preferencesBusyLightURL
        )

        try ScreenshotRenderer.render(
            PreferencesView(renderMode: .screenshot, initialTab: .general)
                .environmentObject(screenshotFixture.settings)
                .environmentObject(screenshotFixture.audio)
                .environmentObject(screenshotFixture.busyLight)
                .environmentObject(screenshotFixture.appState),
            size: NSSize(width: 540, height: 680),
            to: preferencesGeneralURL
        )

        if FileManager.default.fileExists(atPath: legacyPreferencesURL.path) {
            try FileManager.default.removeItem(at: legacyPreferencesURL)
        }
        try FileManager.default.copyItem(at: preferencesOutputURL, to: legacyPreferencesURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: menuBarURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: preferencesOutputURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: preferencesInputURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: preferencesBusyLightURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: preferencesGeneralURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyPreferencesURL.path))
    }

    private func outputDirectoryURL() throws -> URL {
        if let customOutput = ProcessInfo.processInfo.environment[Self.outputPathKey],
           !customOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return URL(fileURLWithPath: customOutput, isDirectory: true)
        }

        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRootURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repoRootURL.appendingPathComponent("docs/screenshots/generated", isDirectory: true)
    }
}

@MainActor
private final class DocumentationScreenshotFixture {
    let settings: AppSettings
    let audio: AudioManager
    let busyLight: BusyLightEngine
    let appState: AppState

    private let defaultsSuiteName: String

    init() {
        defaultsSuiteName = "Sentrio.DocumentationScreenshotTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: defaultsSuiteName) else {
            fatalError("Unable to create isolated UserDefaults suite for screenshot tests.")
        }
        defaults.removePersistentDomain(forName: defaultsSuiteName)

        settings = AppSettings(defaults: defaults)
        audio = AudioManager(mode: .isolated)
        busyLight = BusyLightEngine(audio: audio, settings: settings, mode: .isolated)
        let rules = RulesEngine(audio: audio, settings: settings)
        appState = AppState(
            settings: settings,
            audio: audio,
            rules: rules,
            busyLight: busyLight,
            bindIntegrationBridge: false
        )

        configureSettings()
        configureAudio()
        primeBusyLightSnapshot()
    }

    func shutdown() {
        busyLight.shutdown()
        if let defaults = UserDefaults(suiteName: defaultsSuiteName) {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
    }

    private func configureSettings() {
        settings.isAutoMode = true
        settings.showInputLevelMeter = false
        settings.millisecondsSaved = 1_250_000
        settings.autoSwitchCount = 187
        settings.signalIntegrityScore = 98

        settings.outputPriority = [
            "usb:14ed:1019:mv7plus-serial",
            "bt:airpods-pro2",
            "builtin:speakers",
        ]
        settings.inputPriority = [
            "usb:14ed:1019:mv7plus-serial",
            "builtin:mic",
            "continuity:iphone-hellishsky",
        ]
        settings.disabledOutputDevices = ["bt:jbl-flip6-office"]
        settings.disabledInputDevices = ["usb:blue-yeti-backup"]

        settings.knownDevices = [
            "usb:14ed:1019:mv7plus-serial": "Shure MV7+",
            "usb:14ed:1019:mv7plus-altuid": "Shure MV7+",
            "bt:airpods-pro2": "AirPods Pro",
            "builtin:speakers": "MacBook Pro Speakers",
            "builtin:mic": "MacBook Pro Microphone",
            "continuity:iphone-hellishsky": "HellishSky iPhone",
            "bt:jbl-flip6-office": "JBL Flip 6 (Office)",
            "usb:blue-yeti-backup": "Blue Yeti Backup",
        ]

        settings.knownDeviceTransportTypes = [
            "usb:14ed:1019:mv7plus-serial": .usb,
            "usb:14ed:1019:mv7plus-altuid": .usb,
            "bt:airpods-pro2": .bluetooth,
            "builtin:speakers": .builtIn,
            "builtin:mic": .builtIn,
            "continuity:iphone-hellishsky": .virtual,
            "bt:jbl-flip6-office": .bluetooth,
            "usb:blue-yeti-backup": .usb,
        ]

        settings.knownDeviceModelUIDs = [
            "usb:14ed:1019:mv7plus-serial": "Shure MV7+:14ED:1019",
            "usb:14ed:1019:mv7plus-altuid": "Shure MV7+:14ED:1019",
            "bt:airpods-pro2": "AirPods Pro (2nd generation)",
            "builtin:speakers": "MacBookPro Speakers",
            "builtin:mic": "MacBookPro Microphone",
            "continuity:iphone-hellishsky": "iPhone Mic",
            "bt:jbl-flip6-office": "JBL Flip 6",
            "usb:blue-yeti-backup": "Blue Yeti",
        ]

        settings.deviceIcons = [
            "usb:14ed:1019:mv7plus-serial": ["output": "mic.fill", "input": "mic.fill"],
            "bt:airpods-pro2": ["output": "airpodspro"],
            "continuity:iphone-hellishsky": ["input": "iphone"],
            "bt:jbl-flip6-office": ["output": "speaker.wave.2"],
            "usb:blue-yeti-backup": ["input": "mic"],
        ]
    }

    private func configureAudio() {
        let mv7 = AudioDevice(
            id: AudioDeviceID(101),
            uid: "usb:14ed:1019:mv7plus-serial",
            name: "Shure MV7+",
            hasInput: true,
            hasOutput: true,
            transportType: .usb,
            iconBaseName: "mic",
            modelUID: "Shure MV7+:14ED:1019",
            isAppleMade: false
        )

        let airPods = AudioDevice(
            id: AudioDeviceID(102),
            uid: "bt:airpods-pro2",
            name: "AirPods Pro",
            hasInput: true,
            hasOutput: true,
            transportType: .bluetooth,
            iconBaseName: "airpodspro",
            modelUID: "AirPods Pro (2nd generation)",
            isAppleMade: true,
            batteryStates: [
                .init(kind: .left, level: 0.82),
                .init(kind: .right, level: 0.76),
                .init(kind: .case, level: 0.93),
            ]
        )

        let builtInSpeakers = AudioDevice(
            id: AudioDeviceID(103),
            uid: "builtin:speakers",
            name: "MacBook Pro Speakers",
            hasInput: false,
            hasOutput: true,
            transportType: .builtIn,
            iconBaseName: "speaker"
        )

        let builtInMic = AudioDevice(
            id: AudioDeviceID(104),
            uid: "builtin:mic",
            name: "MacBook Pro Microphone",
            hasInput: true,
            hasOutput: false,
            transportType: .builtIn,
            iconBaseName: "mic"
        )

        let iPhoneContinuity = AudioDevice(
            id: AudioDeviceID(105),
            uid: "continuity:iphone-hellishsky",
            name: "HellishSky iPhone",
            hasInput: true,
            hasOutput: false,
            transportType: .virtual,
            iconBaseName: "iphone",
            modelUID: "iPhone Mic",
            isAppleMade: true
        )

        audio.outputDevices = [mv7, airPods, builtInSpeakers]
        audio.inputDevices = [mv7, airPods, builtInMic, iPhoneContinuity]
        audio.defaultOutput = mv7
        audio.defaultInput = mv7
        audio.outputVolume = 0
        audio.isOutputMuted = true
        audio.inputVolume = 0.68
        audio.alertVolume = 0.45
    }

    func primeBusyLightSnapshot() {
        busyLight.setSnapshotForTesting(
            connectedDevices: [
                BusyLightUSBDevice(
                    id: "1010:2000:desk-light-01",
                    name: "Busylight Omega",
                    vendorID: 1010,
                    productID: 2000,
                    serialNumber: "desk-light-01"
                ),
            ],
            signals: BusyLightSignals(
                microphoneInUse: true,
                cameraInUse: false,
                screenRecordingInUse: false,
                musicPlaying: true
            ),
            currentAction: BusyLightAction.defaultBusy
        )
    }
}

private enum ScreenshotRenderer {
    enum RenderError: Error {
        case bitmapUnavailable
        case encodingFailed
    }

    @MainActor
    static func render(
        _ view: some View,
        size: NSSize,
        maskTopPoints: CGFloat = 0,
        to url: URL
    ) throws {
        _ = NSApplication.shared

        let previousAppearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .aqua)
        defer {
            NSApp.appearance = previousAppearance
        }

        let root = ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            view
            if maskTopPoints > 0 {
                VStack(spacing: 0) {
                    Color(nsColor: .windowBackgroundColor)
                        .frame(height: maskTopPoints)
                    Spacer(minLength: 0)
                }
                .ignoresSafeArea()
            }
        }
        .environment(\.colorScheme, .light)
        .environment(\.controlActiveState, .active)
        .frame(width: size.width, height: size.height)

        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        hostingView.appearance = NSAppearance(named: .aqua)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.hasShadow = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        window.displayIfNeeded()

        RunLoop.main.run(until: Date().addingTimeInterval(0.12))

        guard let representation = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw RenderError.bitmapUnavailable
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)

        guard let pngData = representation.representation(using: .png, properties: [:]) else {
            throw RenderError.encodingFailed
        }
        try pngData.write(to: url, options: .atomic)
        window.orderOut(nil)
    }
}
