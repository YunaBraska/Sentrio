@testable import SentrioCore
import XCTest

final class LocalizationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L10n.overrideLocalization = nil
    }

    private enum LoadError: Error, CustomStringConvertible {
        case missingFile(localization: String)
        case invalidContents(localization: String)

        var description: String {
            switch self {
            case let .missingFile(localization):
                "Missing Localizable.strings for localization: \(localization)"
            case let .invalidContents(localization):
                "Invalid Localizable.strings contents for localization: \(localization)"
            }
        }
    }

    private func loadStrings(localization: String) throws -> [String: String] {
        guard let path = L10n.baseBundle.path(
            forResource: "Localizable",
            ofType: "strings",
            inDirectory: nil,
            forLocalization: localization
        ) else {
            throw LoadError.missingFile(localization: localization)
        }

        guard let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            throw LoadError.invalidContents(localization: localization)
        }
        return dict
    }

    func test_localizations_containAllKeys() throws {
        let en = try loadStrings(localization: "en")
        XCTAssertFalse(en.isEmpty, "en Localizable.strings should not be empty")

        for localization in L10n.supportedLocalizations where localization != "en" {
            let table = try loadStrings(localization: localization)

            let missingKeys = Set(en.keys).subtracting(table.keys)
            XCTAssertTrue(missingKeys.isEmpty, "Missing keys in \(localization): \(missingKeys.sorted())")

            let emptyValues = en.keys.filter { key in
                (table[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            XCTAssertTrue(emptyValues.isEmpty, "Empty values in \(localization): \(emptyValues.sorted())")
        }
    }

    func test_formatPlaceholders_preservedAcrossLocalizations() throws {
        let requiredSubstringsByKey: [String: [String]] = [
            "error.exportFailedFormat": ["%@"],
            "error.importFailedFormat": ["%@"],
            "prefs.iconHelp.withCoreAudioFormat": ["%@"],
            "prefs.savedVolumeFormat": ["%d"],
            "error.importExport.unsupportedSchemaFormat": ["%d"],
        ]

        for localization in L10n.supportedLocalizations {
            let table = try loadStrings(localization: localization)
            for (key, requiredSubstrings) in requiredSubstringsByKey {
                let value = table[key] ?? ""
                for required in requiredSubstrings {
                    XCTAssertTrue(
                        value.contains(required),
                        "Localization \(localization) for key \(key) must contain \(required). Got: \(value)"
                    )
                }
            }
        }
    }
}
