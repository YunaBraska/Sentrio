@testable import SentrioCore
import XCTest

final class AppSoundTests: XCTestCase {
    func test_displayName_none() {
        XCTAssertEqual(AppSound.none.displayName, "None")
    }

    func test_displayName_system() {
        XCTAssertEqual(AppSound.system(name: "Funk").displayName, "Funk")
    }

    func test_displayName_userPreferredAlert() {
        XCTAssertEqual(AppSound.userPreferredAlert.displayName, "System default")
    }

    func test_codableRoundTrip() throws {
        let sounds: [AppSound] = [
            .none,
            .system(name: "Tink"),
            .userPreferredAlert,
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for sound in sounds {
            let data = try encoder.encode(sound)
            let decoded = try decoder.decode(AppSound.self, from: data)
            XCTAssertEqual(decoded, sound)
        }
    }
}
