import CoreAudio
import Foundation

public struct AudioDevice: Identifiable, Hashable, Codable {
    // MARK: – Transport type

    public enum TransportType: String, Codable, CaseIterable {
        case builtIn, bluetooth, usb, airPlay, thunderbolt, hdmi, displayPort
        case aggregate, virtual, pci, unknown

        public var connectionSystemImage: String {
            switch self {
            case .builtIn: "internaldrive"
            case .bluetooth: "wave.3.right"
            case .usb: "cable.connector"
            case .airPlay: "airplayaudio"
            case .thunderbolt: "bolt"
            case .hdmi: "display"
            case .displayPort: "display"
            case .aggregate: "link"
            case .virtual: "waveform.path"
            case .pci: "cpu"
            case .unknown: "questionmark.circle"
            }
        }

        public var label: String {
            switch self {
            case .builtIn: L10n.tr("transport.builtIn")
            case .bluetooth: L10n.tr("transport.bluetooth")
            case .usb: L10n.tr("transport.usb")
            case .airPlay: L10n.tr("transport.airPlay")
            case .thunderbolt: L10n.tr("transport.thunderbolt")
            case .hdmi: L10n.tr("transport.hdmi")
            case .displayPort: L10n.tr("transport.displayPort")
            case .aggregate: L10n.tr("transport.aggregate")
            case .virtual: L10n.tr("transport.virtual")
            case .pci: L10n.tr("transport.pci")
            case .unknown: L10n.tr("transport.unknown")
            }
        }
    }

    // MARK: – Properties

    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public let hasInput: Bool
    public let hasOutput: Bool
    public let transportType: TransportType

    /// Lowercased filename stem from kAudioDevicePropertyIcon — same source Apple System Settings uses.
    /// nil when reconstructed from persisted data (device was disconnected).
    public let iconBaseName: String?

    /// CoreAudio model identifier (kAudioDevicePropertyModelUID).
    /// Often more stable than the user-visible name (e.g. renamed AirPods).
    /// nil when reconstructed from persisted data (device was disconnected).
    public let modelUID: String?

    /// True when the device's icon URL path contains "apple" — i.e. the icon lives in an Apple
    /// framework bundle. Used to improve icon detection for Apple BT devices with renamed names.
    /// False when reconstructed from persisted data (device was disconnected).
    public let isAppleMade: Bool

    /// Bluetooth minor type (from system_profiler), e.g. "Headphones", "Headset", "Phone".
    /// nil when unknown, non-Bluetooth, or reconstructed from persisted data.
    public let bluetoothMinorType: String?

    // MARK: – Battery

    public struct BatteryState: Hashable, Codable {
        public enum Kind: String, Codable, CaseIterable {
            case left, right, `case`, device, other
        }

        public let kind: Kind
        /// Battery fraction [0…1]
        public let level: Float
        /// Optional source name (e.g. a power source name). Not guaranteed stable.
        public let sourceName: String?

        public init(kind: Kind, level: Float, sourceName: String? = nil) {
            self.kind = kind
            self.level = level
            self.sourceName = sourceName
        }

        public var isCase: Bool {
            kind == .case
        }

        public var percent: Int {
            Int((level * 100).rounded())
        }

        public var shortLabel: String {
            switch kind {
            case .left: "L"
            case .right: "R"
            case .case: "C"
            case .device: "B"
            case .other: "•"
            }
        }

        public var shortText: String {
            switch kind {
            case .left, .right, .case:
                "\(shortLabel) \(percent)%"
            case .device, .other:
                "\(percent)%"
            }
        }

        public var systemImage: String {
            AudioDevice.batterySystemImage(for: level)
        }
    }

    /// Battery states (0…N). Empty when not reported.
    public let batteryStates: [BatteryState]

    // MARK: – Equatable / Hashable

    public static func == (lhs: AudioDevice, rhs: AudioDevice) -> Bool {
        lhs.uid == rhs.uid
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(uid)
    }

    // MARK: – Codable (live-only fields excluded)

    enum CodingKeys: String, CodingKey { case uid, name, hasInput, hasOutput, transportType }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uid = try c.decode(String.self, forKey: .uid)
        name = try c.decode(String.self, forKey: .name)
        hasInput = try c.decode(Bool.self, forKey: .hasInput)
        hasOutput = try c.decode(Bool.self, forKey: .hasOutput)
        transportType = try c.decodeIfPresent(TransportType.self, forKey: .transportType) ?? .unknown
        id = kAudioObjectUnknown
        iconBaseName = nil
        modelUID = nil
        isAppleMade = false
        bluetoothMinorType = nil
        batteryStates = []
    }

    public init(
        id: AudioDeviceID = kAudioObjectUnknown,
        uid: String,
        name: String,
        hasInput: Bool,
        hasOutput: Bool,
        transportType: TransportType = .unknown,
        iconBaseName: String? = nil,
        modelUID: String? = nil,
        isAppleMade: Bool = false,
        bluetoothMinorType: String? = nil,
        batteryStates: [BatteryState] = []
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.hasInput = hasInput
        self.hasOutput = hasOutput
        self.transportType = transportType
        self.iconBaseName = iconBaseName
        self.modelUID = modelUID
        self.isAppleMade = isAppleMade
        self.bluetoothMinorType = bluetoothMinorType
        self.batteryStates = batteryStates
    }

    // MARK: – Battery helpers

    public static func batterySystemImage(for level: Float) -> String {
        switch level {
        case ..<0.15: "battery.0percent"
        case ..<0.40: "battery.25percent"
        case ..<0.70: "battery.50percent"
        case ..<0.90: "battery.75percent"
        default: "battery.100percent"
        }
    }

    /// Lowest battery level across all states excluding charging cases (e.g. AirPods case).
    public var lowestNonCaseBatteryLevel: Float? {
        batteryStates.filter { !$0.isCase }.map(\.level).min()
    }

    // MARK: – Volume-reactive speaker icon

    //
    // When a device's icon is one of the standard speaker symbols (the macOS default),
    // we swap it for a volume-reactive variant — same behaviour as the macOS Sound Settings icon.

    private static let speakerFamily: Set<String> = [
        "speaker", "speaker.fill",
        "speaker.wave.1", "speaker.wave.1.fill",
        "speaker.wave.2", "speaker.wave.2.fill",
        "speaker.wave.3", "speaker.wave.3.fill",
        "speaker.slash", "speaker.slash.fill",
        "hifispeaker", "hifispeaker.fill",
    ]

    /// If `icon` is a standard speaker symbol, returns a volume-level variant (mirrors System Settings).
    /// All other icons are returned unchanged.
    public static func volumeAdaptedIcon(_ icon: String, volume: Float, isMuted: Bool = false) -> String {
        guard speakerFamily.contains(icon) else { return icon }
        if isMuted || volume <= 0.001 { return "speaker.slash" }
        switch volume {
        case ..<0.34: return "speaker.wave.1"
        case ..<0.67: return "speaker.wave.2"
        default: return "speaker.wave.3"
        }
    }

    // MARK: – Device-type icon

    //
    // Resolution order (mirrors Apple System Settings):
    //   1. CoreAudio icon file stem  (kAudioDevicePropertyIcon)
    //   2. Name heuristics
    //   3. Apple Bluetooth fallback  (manufacturer = "Apple Inc." + BT transport)
    //   4. Transport-type connection icon

    /// Maps the lowercased icon filename stem from kAudioDevicePropertyIcon to an SF Symbol.
    /// Covers known Apple device families; extend as new hardware ships.
    private static let iconFileToSymbol: [String: String] = [
        // AirPods Pro (various internal names Apple uses across generations)
        "airpodspro": "airpodspro",
        "airpodsproheadphones": "airpodspro",
        "airpodsheadphonespro": "airpodspro",
        "airpodsheadphonespro2": "airpodspro",
        "airpodspro2": "airpodspro",
        "airpodsproushp": "airpodspro",
        "airpodsproushp2": "airpodspro",
        // AirPods (standard)
        "airpods": "airpods",
        "airpodsheadphones": "airpods",
        "airpods3": "airpods",
        "airpodsheadphones3": "airpods",
        "airpods2": "airpods",
        // AirPods Max
        "airpodsmax": "airpodsmax",
        "airpodsheadphonesmax": "airpodsmax",
        "airpodsmax2": "airpodsmax",
        // EarPods / Beats
        "earpods": "earbuds",
        "headphones": "headphones",
        "beatsstudio": "headphones",
        "beatsstudio3": "headphones",
        "beatssolo": "headphones",
        "beatsheadphones": "headphones",
        "beatsearphones": "earbuds",
        // HomePod
        "homepodmini": "homepodmini",
        "homepod": "homepod",
        "homepod2": "homepod",
        // Apple devices
        "iphone": "iphone",
        "ipad": "ipad",
        "applewatch": "applewatch",
        "macbook": "laptopcomputer",
        "macbookpro": "laptopcomputer",
        "macbookair": "laptopcomputer",
        "macmini": "macmini",
        "imac": "desktopcomputer",
        "appletv": "appletv",
    ]

    /// Returns the best SF Symbol for this device. Used as the default when no custom icon is set.
    public var deviceTypeSystemImage: String {
        // 1. CoreAudio icon file → SF Symbol (most accurate — same source as System Settings)
        if let stem = iconBaseName {
            if let symbol = Self.iconFileToSymbol[stem] { return symbol }
            // Some icon stems include extra suffixes/prefixes (generation, region, etc.).
            // Best-effort substring matching keeps icons correct even as Apple ships new variants.
            if stem.contains("airpodspro") { return "airpodspro" }
            if stem.contains("airpodsmax") { return "airpodsmax" }
            if stem.contains("airpods") { return "airpods" }
            if stem.contains("earpods") { return "earbuds" }
            if stem.contains("homepodmini") { return "homepodmini" }
            if stem.contains("homepod") { return "homepod" }
            if stem.contains("beats") { return "headphones" }
            if stem.contains("iphone") { return "iphone" }
            if stem.contains("ipad") { return "ipad" }
            if stem.contains("applewatch") { return "applewatch" }
            if stem.contains("macbook") { return "laptopcomputer" }
            if stem.contains("macmini") { return "macmini" }
            if stem.contains("imac") { return "desktopcomputer" }
            if stem.contains("appletv") { return "appletv" }
            if stem.contains("display") || stem.contains("monitor") { return "display" }
        }

        // 2. ModelUID heuristics (often stable even when user renames the device)
        if let modelUIDLower = modelUID?.lowercased() {
            if modelUIDLower.contains("homepod mini") { return "homepodmini" }
            if modelUIDLower.contains("homepod") { return "homepod" }
            if modelUIDLower.contains("iphone") { return "iphone" }
            if modelUIDLower.contains("ipad") { return "ipad" }
            if modelUIDLower.contains("apple watch") { return "applewatch" }
            if modelUIDLower.contains("earpods") { return "earbuds" }
            if modelUIDLower.contains("microphone") || modelUIDLower.contains(" mic") { return "mic" }
            if modelUIDLower == "speaker", hasOutput, !hasInput { return "speaker.wave.2" }

            if let ids = Self.appleVendorProduct(fromModelUID: modelUIDLower) {
                let productID = ids.productID
                // Best-effort Apple audio model mapping. Extend as new IDs are discovered.
                if Self.appleAirPodsProProductIDs.contains(productID) { return "airpodspro" }
                if Self.appleAirPodsMaxProductIDs.contains(productID) { return "airpodsmax" }
                if hasOutput,
                   batteryStates.contains(where: { $0.kind == .left || $0.kind == .right })
                {
                    return "airpods"
                }
            }
        }

        // 2. Name heuristics
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("earpods") { return "earbuds" }
        if hasOutput, n.contains("beats") { return "headphones" }
        if hasOutput,
           n.contains("bose") || n.contains("sony") || n.contains("jabra") || n.contains("sennheiser")
        { return "headphones" }
        if n.contains("headphone") || n.contains("headset") { return "headphones" }
        if n.contains("homepod mini") { return "homepodmini" }
        if n.contains("homepod") { return "homepod" }
        if n.contains("apple watch") { return "applewatch" }
        if n.contains("iphone") { return "iphone" }
        if n.contains("ipad") { return "ipad" }
        if n.contains("mac") { return "laptopcomputer" }
        if n.contains("built-in") && hasOutput && !hasInput { return "speaker.wave.2" }
        if n.contains("built-in") && hasInput && !hasOutput { return "mic" }
        if n.contains("built-in") { return "macmini" }
        if n.contains("speaker") || n.contains("output") { return "hifispeaker" }
        if n.contains("microphone") || n.contains("mic") { return "mic" }
        if n.contains("display") || n.contains("monitor") { return "display" }
        if n.contains("usb") { return "cable.connector" }

        // 3. Apple Bluetooth fallback — catches Apple devices with user-renamed names
        //    (e.g. AirPods named "[Yuna] ClayWave") where icon file lookup and name matching both miss.
        //    isAppleMade is derived from the icon URL path — Apple device icons live in Apple
        //    framework bundles, so no separate CoreAudio property read is needed.
        if transportType == .bluetooth, let minor = bluetoothMinorType?.lowercased() {
            if minor.contains("headphone") || minor.contains("headset") {
                if isAppleMade,
                   hasOutput,
                   batteryStates.contains(where: { $0.kind == .left || $0.kind == .right })
                {
                    return "airpods"
                }
                return "headphones"
            }
            if minor.contains("speaker") { return "hifispeaker" }
            if minor.contains("phone") { return "iphone" }
            if minor.contains("tablet") { return "ipad" }
            if minor.contains("computer") || minor.contains("mac") { return "laptopcomputer" }
            if minor.contains("watch") { return "applewatch" }
        }

        if transportType == .bluetooth,
           isAppleMade,
           hasOutput,
           batteryStates.contains(where: { $0.kind == .left || $0.kind == .right })
        {
            return "airpods"
        }

        // 4. Fallback by I/O capability before transport type
        if hasOutput, hasInput { return "headphones" }

        // 4. Transport-type fallback
        return transportType.connectionSystemImage
    }

    // MARK: – ModelUID helpers

    private struct AppleVendorProductIDs {
        let productID: Int
        let vendorID: Int
    }

    /// Parses CoreAudio ModelUID formats like "2014 4c" (hex product + hex vendor).
    private static func appleVendorProduct(fromModelUID modelUIDLower: String) -> AppleVendorProductIDs? {
        let parts = modelUIDLower.split(whereSeparator: \.isWhitespace)
        guard parts.count == 2 else { return nil }
        guard
            let product = Int(parts[0], radix: 16),
            let vendor = Int(parts[1], radix: 16),
            vendor == 0x004C
        else { return nil }
        return AppleVendorProductIDs(productID: product, vendorID: vendor)
    }

    // Observed on local systems; incomplete by design (unknown IDs fall back to generic AirPods icon).
    private static let appleAirPodsProProductIDs: Set<Int> = [0x2014]
    private static let appleAirPodsMaxProductIDs: Set<Int> = []
}
