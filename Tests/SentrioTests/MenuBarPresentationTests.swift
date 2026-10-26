@testable import SentrioCore
import XCTest

final class MenuBarPresentationTests: XCTestCase {
    func testMenuBarIconIsVisibleWithoutExplicitHideSetting() {
        XCTAssertTrue(MenuBarPresentation.statusItemIsVisible(hidingMenuBarIcon: false))
        XCTAssertEqual(MenuBarPresentation.activationPolicy(hidingMenuBarIcon: false), .accessory)
    }

    func testHiddenMenuBarIconKeepsTheAppReachableFromTheDock() {
        XCTAssertFalse(MenuBarPresentation.statusItemIsVisible(hidingMenuBarIcon: true))
        XCTAssertEqual(MenuBarPresentation.activationPolicy(hidingMenuBarIcon: true), .regular)
    }
}
