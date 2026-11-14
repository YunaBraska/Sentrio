@testable import SentrioCore
import XCTest

final class MenuBarPresentationTests: XCTestCase {
    func testPopoverKeepsPreferredWidthWhenTheScreenHasRoom() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)

        XCTAssertEqual(MenuBarPresentation.popoverWidth(for: visibleFrame), 370)
    }

    func testPopoverShrinksToTheVisibleScreenAtTheDisplayEdge() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 274, height: 900)

        XCTAssertEqual(MenuBarPresentation.popoverWidth(for: visibleFrame), 250)
    }

    func testPopoverFrameIsClampedInsideTheVisibleScreen() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 600, height: 900)
        let overflowingFrame = NSRect(x: 400, y: 400, width: 370, height: 520)

        XCTAssertEqual(
            MenuBarPresentation.clampedPopoverOrigin(
                popoverFrame: overflowingFrame,
                visibleFrame: visibleFrame
            ),
            NSPoint(x: 218, y: 368)
        )
    }

    func testPopoverFrameHandlesDisplaysWithNegativeCoordinates() {
        let visibleFrame = NSRect(x: -1728, y: 0, width: 1728, height: 1080)
        let overflowingFrame = NSRect(x: -1800, y: -40, width: 370, height: 700)

        XCTAssertEqual(
            MenuBarPresentation.clampedPopoverOrigin(
                popoverFrame: overflowingFrame,
                visibleFrame: visibleFrame
            ),
            NSPoint(x: -1716, y: 12)
        )
    }

    func testMenuBarIconIsVisibleWithoutExplicitHideSetting() {
        XCTAssertTrue(MenuBarPresentation.statusItemIsVisible(hidingMenuBarIcon: false))
        XCTAssertEqual(MenuBarPresentation.activationPolicy(hidingMenuBarIcon: false), .accessory)
    }

    func testHiddenMenuBarIconKeepsTheAppReachableFromTheDock() {
        XCTAssertFalse(MenuBarPresentation.statusItemIsVisible(hidingMenuBarIcon: true))
        XCTAssertEqual(MenuBarPresentation.activationPolicy(hidingMenuBarIcon: true), .regular)
    }
}
