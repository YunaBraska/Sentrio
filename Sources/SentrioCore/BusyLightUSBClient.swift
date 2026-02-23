import Foundation
import IOKit.hid

struct BusyLightUSBDevice: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var vendorID: Int
    var productID: Int
    var serialNumber: String?
}

struct BusyLightUSBSendResult: Codable, Equatable {
    var deviceID: String
    var deviceName: String
    var statusCode: Int32
    var recoveredAfterRetry: Bool

    var isSuccess: Bool { statusCode == Int32(kIOReturnSuccess) }
}

final class BusyLightUSBClient: ObservableObject {
    @Published private(set) var devices: [BusyLightUSBDevice] = []

    private let manager: IOHIDManager
    private var hidDevices: [String: IOHIDDevice] = [:]

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let match: [[String: Any]] = [
            // PLENOM / Kuando (0x27BB)
            [kIOHIDVendorIDKey as String: 0x27BB],
            // Older Microchip VID used by some models (seen in reference implementations)
            [kIOHIDVendorIDKey as String: 1240],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, match as CFArray)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            let client = Unmanaged<BusyLightUSBClient>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                client.addDevice(device)
            }
        }, ctx)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let client = Unmanaged<BusyLightUSBClient>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                client.removeDevice(device)
            }
        }, ctx)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        // Seed devices list if already connected
        refreshDevicesFromManager()
    }

    deinit {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    @discardableResult
    func setSolidColor(_ color: BusyLightColor) -> [BusyLightUSBSendResult] {
        sendColor(color)
    }

    @discardableResult
    func turnOff() -> [BusyLightUSBSendResult] {
        sendColor(.offColor)
    }

    // MARK: - Private

    private func refreshDevicesFromManager() {
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }
        for dev in set {
            addDevice(dev)
        }
    }

    private func addDevice(_ device: IOHIDDevice) {
        let descriptor = describe(device)
        let key = descriptor.id
        guard hidDevices[key] == nil else { return }

        IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        hidDevices[key] = device

        rebuildPublishedDevices()
    }

    private func removeDevice(_ device: IOHIDDevice) {
        let descriptor = describe(device)
        let key = descriptor.id
        guard let existing = hidDevices.removeValue(forKey: key) else { return }
        IOHIDDeviceClose(existing, IOOptionBits(kIOHIDOptionsTypeNone))

        rebuildPublishedDevices()
    }

    private func rebuildPublishedDevices() {
        devices = hidDevices.values.map(describe).sorted { $0.name < $1.name }
    }

    private func sendColor(_ color: BusyLightColor) -> [BusyLightUSBSendResult] {
        let report = Self.makeOutputReport(color: color)
        guard !hidDevices.isEmpty else { return [] }
        var results: [BusyLightUSBSendResult] = []
        for device in hidDevices.values {
            let descriptor = describe(device)
            report.withUnsafeBytes { buf in
                var result = IOHIDDeviceSetReport(
                    device,
                    kIOHIDReportTypeOutput,
                    CFIndex(0),
                    buf.bindMemory(to: UInt8.self).baseAddress!,
                    buf.count
                )
                var recovered = false
                guard result != kIOReturnSuccess else { return }

                // Some devices occasionally stop accepting reports when spammed
                // (e.g. repeated previews/pulse). Try a close+open recovery once.
                IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
                IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
                result = IOHIDDeviceSetReport(
                    device,
                    kIOHIDReportTypeOutput,
                    CFIndex(0),
                    buf.bindMemory(to: UInt8.self).baseAddress!,
                    buf.count
                )
                recovered = result == kIOReturnSuccess

                results.append(BusyLightUSBSendResult(
                    deviceID: descriptor.id,
                    deviceName: descriptor.name,
                    statusCode: result,
                    recoveredAfterRetry: recovered
                ))
            }

            if results.last?.deviceID != descriptor.id {
                results.append(BusyLightUSBSendResult(
                    deviceID: descriptor.id,
                    deviceName: descriptor.name,
                    statusCode: Int32(kIOReturnSuccess),
                    recoveredAfterRetry: false
                ))
            }
        }
        return results
    }

    static func makeOutputReport(color: BusyLightColor) -> [UInt8] {
        // 64-byte report payload, matching the Busylight HID protocol (rev 2.2).
        // Programs step 0 with a long on-time. Some firmware variants still
        // require periodic keepalives, which BusyLightEngine sends in solid mode.
        //
        // Note: RGB intensities are 0...100 (%), not 0...255.
        var data = Array(repeating: UInt8(0), count: 64)
        data[0] = 0x10 // step 0: jump to step 0
        data[1] = 0xFF // repeat 255 times then jump (effectively infinite loop)
        data[2] = percentIntensity(from: color.red)
        data[3] = percentIntensity(from: color.green)
        data[4] = percentIntensity(from: color.blue)
        data[5] = 0xFF // on_time: 25.5s
        data[6] = 0x00 // off_time: 0s
        data[7] = 0x80 // ringtone: force sound off

        // Additional data (56..61)
        data[56] = 0
        data[57] = 0
        data[58] = 255
        data[59] = 255
        data[60] = 255
        data[61] = 255

        // Checksum over bytes 0..61
        let checksum = data[0 ..< 62].reduce(0) { $0 + Int($1) }
        data[62] = UInt8((checksum >> 8) & 0xFF)
        data[63] = UInt8(checksum & 0xFF)

        return data
    }

    private static func percentIntensity(from component: UInt8) -> UInt8 {
        let pct = Int((Double(component) / 255.0 * 100.0).rounded())
        return UInt8(max(0, min(100, pct)))
    }

    private func describe(_ device: IOHIDDevice) -> BusyLightUSBDevice {
        func intProperty(_ key: String) -> Int? {
            (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
        }
        func stringProperty(_ key: String) -> String? {
            IOHIDDeviceGetProperty(device, key as CFString) as? String
        }

        let vendorID = intProperty(kIOHIDVendorIDKey as String) ?? -1
        let productID = intProperty(kIOHIDProductIDKey as String) ?? -1
        let serialNumber = stringProperty(kIOHIDSerialNumberKey as String)
        let name = stringProperty(kIOHIDProductKey as String) ?? "BusyLight"

        let fallback = intProperty(kIOHIDLocationIDKey as String)
        let pointerID = String(UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque()))
        let disambiguator = serialNumber ?? fallback.map(String.init) ?? pointerID
        let id = "\(vendorID):\(productID):\(disambiguator)"

        return BusyLightUSBDevice(
            id: id,
            name: name,
            vendorID: vendorID,
            productID: productID,
            serialNumber: serialNumber
        )
    }
}
