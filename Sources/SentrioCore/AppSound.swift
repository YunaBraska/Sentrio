import AppKit
import AudioToolbox
import Foundation

enum AppSound: Codable, Hashable {
    case none
    case system(name: String)
    case userPreferredAlert

    static let defaultTestSound: AppSound = .system(name: "Funk")
    static let defaultAlertSound: AppSound = .userPreferredAlert

    var displayName: String {
        switch self {
        case .none:
            "None"
        case let .system(name):
            name
        case .userPreferredAlert:
            "System default"
        }
    }
}

enum SoundLibrary {
    static func systemSoundNames() -> [String] {
        let fileManager = FileManager.default
        let dirs: [URL] = [
            URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true),
            URL(fileURLWithPath: "/Library/Sounds", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds", isDirectory: true),
        ]

        var names = Set<String>()
        for dir in dirs {
            guard let items = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in items where url.hasSoundExtension {
                names.insert(url.deletingPathExtension().lastPathComponent)
            }
        }

        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func play(_ sound: AppSound) {
        switch sound {
        case .none:
            return
        case .userPreferredAlert:
            AudioServicesPlayAlertSound(kSystemSoundID_UserPreferredAlert)
        case let .system(name):
            if let s = NSSound(named: NSSound.Name(name)) {
                s.play()
                return
            }
            if let url = urlForSystemSound(named: name) {
                NSSound(contentsOf: url, byReference: true)?.play()
            }
        }
    }

    private static func urlForSystemSound(named name: String) -> URL? {
        let fileManager = FileManager.default
        let dirs: [URL] = [
            URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true),
            URL(fileURLWithPath: "/Library/Sounds", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds", isDirectory: true),
        ]

        for dir in dirs {
            guard let items = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            if let match = items.first(where: {
                $0.hasSoundExtension && $0.deletingPathExtension().lastPathComponent == name
            }) {
                return match
            }
        }
        return nil
    }
}

private extension URL {
    var hasSoundExtension: Bool {
        switch pathExtension.lowercased() {
        case "aiff", "wav", "caf", "mp3", "m4a":
            true
        default:
            false
        }
    }
}
