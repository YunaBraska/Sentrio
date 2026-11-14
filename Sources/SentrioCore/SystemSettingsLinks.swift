import Foundation

enum SystemSettingsLinks {
    static let sound = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!
    static let microphonePrivacy = URL(
        string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone"
    )!
    static let bluetooth = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!
}
