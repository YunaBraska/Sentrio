import CoreAudio
import Foundation

public struct AudioDevice: Identifiable, Hashable, Codable {

    // MARK: – Transport type

    public enum TransportType: String, Codable, CaseIterable {
        case builtIn, bluetooth, usb, airPlay, thunderbolt, hdmi, displayPort
        case aggregate, virtual, pci, unknown

        public var connectionSystemImage: String {
            switch self {
            case .builtIn:      return "internaldrive"
            case .bluetooth:    return "wave.3.right"
            case .usb:          return "cable.connector"
            case .airPlay:      return "airplayaudio"
            case .thunderbolt:  return "bolt"
            case .hdmi:         return "display"
            case .displayPort:  return "display"
            case .aggregate:    return "link"
            case .virtual:      return "waveform.path"
            case .pci:          return "cpu"
            case .unknown:      return "questionmark.circle"
            }
        }

        public var label: String {
            switch self {
            case .builtIn:      return "Built-in"
            case .bluetooth:    return "Bluetooth"
            case .usb:          return "USB"
            case .airPlay:      return "AirPlay"
            case .thunderbolt:  return "Thunderbolt"
            case .hdmi:         return "HDMI"
            case .displayPort:  return "DisplayPort"
            case .aggregate:    return "Aggregate"
            case .virtual:      return "Virtual"
            case .pci:          return "PCI"
            case .unknown:      return "Unknown"
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

    /// True when the device's icon URL path contains "apple" — i.e. the icon lives in an Apple
    /// framework bundle. Used to improve icon detection for Apple BT devices with renamed names.
    /// False when reconstructed from persisted data (device was disconnected).
    public let isAppleMade: Bool

    /// Battery level [0…1] from kAudioDevicePropertyBatteryLevel. nil if device has no battery.
    public let batteryLevel: Float?

    // MARK: – Equatable / Hashable

    public static func == (lhs: AudioDevice, rhs: AudioDevice) -> Bool { lhs.uid == rhs.uid }
    public func hash(into hasher: inout Hasher) { hasher.combine(uid) }

    // MARK: – Codable (live-only fields excluded)

    enum CodingKeys: String, CodingKey { case uid, name, hasInput, hasOutput, transportType }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uid           = try c.decode(String.self,        forKey: .uid)
        name          = try c.decode(String.self,        forKey: .name)
        hasInput      = try c.decode(Bool.self,          forKey: .hasInput)
        hasOutput     = try c.decode(Bool.self,          forKey: .hasOutput)
        transportType = try c.decodeIfPresent(TransportType.self, forKey: .transportType) ?? .unknown
        id            = kAudioObjectUnknown
        iconBaseName  = nil
        isAppleMade   = false
        batteryLevel  = nil
    }

    public init(
        id: AudioDeviceID = kAudioObjectUnknown,
        uid: String,
        name: String,
        hasInput: Bool,
        hasOutput: Bool,
        transportType: TransportType = .unknown,
        iconBaseName: String? = nil,
        isAppleMade: Bool = false,
        batteryLevel: Float? = nil
    ) {
        self.id           = id
        self.uid          = uid
        self.name         = name
        self.hasInput     = hasInput
        self.hasOutput    = hasOutput
        self.transportType = transportType
        self.iconBaseName = iconBaseName
        self.isAppleMade  = isAppleMade
        self.batteryLevel = batteryLevel
    }

    // MARK: – Battery indicator

    /// SF Symbol for the current battery level. nil when device has no battery.
    public var batterySystemImage: String? {
        guard let level = batteryLevel else { return nil }
        switch level {
        case ..<0.15: return "battery.0percent"
        case ..<0.40: return "battery.25percent"
        case ..<0.70: return "battery.50percent"
        case ..<0.90: return "battery.75percent"
        default:      return "battery.100percent"
        }
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
    public static func volumeAdaptedIcon(_ icon: String, volume: Float) -> String {
        guard speakerFamily.contains(icon) else { return icon }
        switch volume {
        case 0:       return "speaker.slash"
        case ..<0.34: return "speaker.wave.1"
        case ..<0.67: return "speaker.wave.2"
        default:      return "speaker.wave.3"
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
        "airpodspro":                   "airpodspro",
        "airpodsproheadphones":         "airpodspro",
        "airpodsheadphonespro":         "airpodspro",
        "airpodsheadphonespro2":        "airpodspro",
        "airpodspro2":                  "airpodspro",
        "airpodsproushp":               "airpodspro",
        "airpodsproushp2":              "airpodspro",
        // AirPods (standard)
        "airpods":                      "airpods",
        "airpodsheadphones":            "airpods",
        "airpods3":                     "airpods",
        "airpodsheadphones3":           "airpods",
        "airpods2":                     "airpods",
        // AirPods Max
        "airpodsmax":                   "airpodsmax",
        "airpodsheadphonesmax":         "airpodsmax",
        "airpodsmax2":                  "airpodsmax",
        // EarPods / Beats
        "earpods":                      "earbuds",
        "headphones":                   "headphones",
        "beatsstudio":                  "headphones",
        "beatsstudio3":                 "headphones",
        "beatssolo":                    "headphones",
        "beatsheadphones":              "headphones",
        "beatsearphones":               "earbuds",
        // HomePod
        "homepodmini":                  "homepodmini",
        "homepod":                      "homepod",
        "homepod2":                     "homepod",
        // Apple devices
        "iphone":                       "iphone",
        "ipad":                         "ipad",
        "applewatch":                   "applewatch",
        "macbook":                      "laptopcomputer",
        "macbookpro":                   "laptopcomputer",
        "macbookair":                   "laptopcomputer",
        "macmini":                      "macmini",
        "imac":                         "desktopcomputer",
        "appletv":                      "appletv",
    ]

    /// Returns the best SF Symbol for this device. Used as the default when no custom icon is set.
    public var deviceTypeSystemImage: String {
        // 1. CoreAudio icon file → SF Symbol (most accurate — same source as System Settings)
        if let stem = iconBaseName, let symbol = Self.iconFileToSymbol[stem] { return symbol }

        // 2. Name heuristics
        let n = name.lowercased()
        if n.contains("airpods max")                            { return "airpodsmax" }
        if n.contains("airpods pro")                            { return "airpodspro" }
        if n.contains("airpods")                                { return "airpods" }
        if n.contains("earpods")                                { return "earbuds" }
        if n.contains("headphone") || n.contains("headset")    { return "headphones" }
        if n.contains("homepod mini")                           { return "homepodmini" }
        if n.contains("homepod")                                { return "homepod" }
        if n.contains("apple watch")                            { return "applewatch" }
        if n.contains("iphone")                                 { return "iphone" }
        if n.contains("ipad")                                   { return "ipad" }
        if n.contains("mac")                                    { return "laptopcomputer" }
        if n.contains("built-in") && hasOutput && !hasInput     { return "speaker.wave.2" }
        if n.contains("built-in") && hasInput  && !hasOutput    { return "mic" }
        if n.contains("built-in")                               { return "macmini" }
        if n.contains("speaker") || n.contains("output")        { return "hifispeaker" }
        if n.contains("microphone") || n.contains("mic")        { return "mic" }
        if n.contains("display") || n.contains("monitor")       { return "display" }
        if n.contains("usb")                                    { return "cable.connector" }

        // 3. Apple Bluetooth fallback — catches Apple devices with user-renamed names
        //    (e.g. AirPods named "[Yuna] ClayWave") where icon file lookup and name matching both miss.
        //    isAppleMade is derived from the icon URL path — Apple device icons live in Apple
        //    framework bundles, so no separate CoreAudio property read is needed.
        if transportType == .bluetooth, isAppleMade {
            return "airpods"
        }

        // 4. Transport-type fallback
        return transportType.connectionSystemImage
    }
}
