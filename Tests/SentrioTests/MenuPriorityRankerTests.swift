@testable import SentrioCore
import XCTest

final class MenuPriorityRankerTests: XCTestCase {
    func test_rankMap_assignsContiguousRanksForVisibleRows() {
        let result = MenuPriorityRanker.rankMap(for: ["A", "C", "D"])
        XCTAssertEqual(result["A"], 1)
        XCTAssertEqual(result["C"], 2)
        XCTAssertEqual(result["D"], 3)
        XCTAssertEqual(result.count, 3)
    }

    func test_rankMap_ignoresDuplicateUIDs() {
        let result = MenuPriorityRanker.rankMap(for: ["A", "B", "A", "C", "B"])
        XCTAssertEqual(result["A"], 1)
        XCTAssertEqual(result["B"], 2)
        XCTAssertEqual(result["C"], 3)
        XCTAssertEqual(result.count, 3)
    }

    func test_rankMap_emptyInputProducesEmptyMap() {
        XCTAssertTrue(MenuPriorityRanker.rankMap(for: []).isEmpty)
    }

    func test_reorderPath_returnsNextUIDWhenMovingDown() {
        let uid = MenuPriorityReorderPath.targetUID(
            for: "B",
            direction: 1,
            orderedUIDs: ["A", "B", "C", "D"]
        )
        XCTAssertEqual(uid, "C")
    }

    func test_reorderPath_returnsPreviousUIDWhenMovingUp() {
        let uid = MenuPriorityReorderPath.targetUID(
            for: "C",
            direction: -1,
            orderedUIDs: ["A", "B", "C", "D"]
        )
        XCTAssertEqual(uid, "B")
    }

    func test_reorderPath_returnsNilWhenSourceMissing() {
        let uid = MenuPriorityReorderPath.targetUID(
            for: "X",
            direction: 1,
            orderedUIDs: ["A", "B", "C"]
        )
        XCTAssertNil(uid)
    }

    func test_reorderPath_returnsNilAtBoundaries() {
        XCTAssertNil(MenuPriorityReorderPath.targetUID(
            for: "A",
            direction: -1,
            orderedUIDs: ["A", "B", "C"]
        ))
        XCTAssertNil(MenuPriorityReorderPath.targetUID(
            for: "C",
            direction: 1,
            orderedUIDs: ["A", "B", "C"]
        ))
    }

    func test_reorderPath_rejectsInvalidDirection() {
        XCTAssertNil(MenuPriorityReorderPath.targetUID(
            for: "B",
            direction: 0,
            orderedUIDs: ["A", "B", "C"]
        ))
    }
}
