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
}
