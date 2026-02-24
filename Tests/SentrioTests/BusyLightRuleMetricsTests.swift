@testable import SentrioCore
import XCTest

final class BusyLightRuleMetricsTests: XCTestCase {
    func test_recordInterval_updatesTotalAndRecentIntervals() {
        var metrics = BusyLightRuleMetrics()
        let start = date(milliseconds: 1000)
        let end = date(milliseconds: 5000)

        metrics.recordInterval(start: start, end: end, now: end)

        XCTAssertEqual(metrics.totalActiveMilliseconds, 4000)
        XCTAssertEqual(metrics.recentIntervals.count, 1)
        XCTAssertEqual(metrics.recentIntervals[0], BusyLightRuleActiveInterval(
            startEpochMilliseconds: 1000,
            endEpochMilliseconds: 5000
        ))
    }

    func test_recordInterval_ignoresNonPositiveDuration() {
        var metrics = BusyLightRuleMetrics()
        let timestamp = date(milliseconds: 10000)

        metrics.recordInterval(start: timestamp, end: timestamp, now: timestamp)
        metrics.recordInterval(start: timestamp, end: date(milliseconds: 9000), now: timestamp)

        XCTAssertEqual(metrics.totalActiveMilliseconds, 0)
        XCTAssertTrue(metrics.recentIntervals.isEmpty)
    }

    func test_pruneRecentIntervals_dropsIntervalsOutsideRollingYearWindow() {
        let now = date(milliseconds: BusyLightRuleMetrics.yearMilliseconds + 10000)
        var metrics = BusyLightRuleMetrics(
            totalActiveMilliseconds: 100,
            recentIntervals: [
                BusyLightRuleActiveInterval(startEpochMilliseconds: 0, endEpochMilliseconds: 1000),
                BusyLightRuleActiveInterval(
                    startEpochMilliseconds: BusyLightRuleMetrics.dayMilliseconds,
                    endEpochMilliseconds: BusyLightRuleMetrics.dayMilliseconds + 2000
                ),
            ]
        )

        metrics.pruneRecentIntervals(now: now)

        XCTAssertEqual(metrics.recentIntervals.count, 1)
        XCTAssertEqual(metrics.recentIntervals[0].startEpochMilliseconds, BusyLightRuleMetrics.dayMilliseconds)
    }

    func test_activeMillisecondsInLastWindow_countsPartialOverlap() {
        let now = date(milliseconds: 15000)
        let metrics = BusyLightRuleMetrics(
            totalActiveMilliseconds: 20000,
            recentIntervals: [
                BusyLightRuleActiveInterval(startEpochMilliseconds: 0, endEpochMilliseconds: 4000),
                BusyLightRuleActiveInterval(startEpochMilliseconds: 8000, endEpochMilliseconds: 14000),
            ]
        )

        let active = metrics.activeMilliseconds(inLast: 10000, now: now)

        // Window is [5_000 ... 15_000], so only [8_000 ... 14_000] overlaps.
        XCTAssertEqual(active, 6000)
    }

    func test_summary_usesRollingAveragesForDayMonthYear() {
        let day = BusyLightRuleMetrics.dayMilliseconds
        let nowMs = BusyLightRuleMetrics.yearMilliseconds + (10 * day)
        let now = date(milliseconds: nowMs)

        let sixHours = Int64(6 * 60 * 60 * 1000)
        let oneDay = day
        let fiveDays = Int64(5 * day)

        let metrics = BusyLightRuleMetrics(
            totalActiveMilliseconds: sixHours + oneDay + fiveDays,
            recentIntervals: [
                // Last day: 6h.
                BusyLightRuleActiveInterval(
                    startEpochMilliseconds: nowMs - sixHours,
                    endEpochMilliseconds: nowMs
                ),
                // In month window, outside day window: +1d.
                BusyLightRuleActiveInterval(
                    startEpochMilliseconds: nowMs - (10 * day),
                    endEpochMilliseconds: nowMs - (9 * day)
                ),
                // In year window, outside month window: +5d.
                BusyLightRuleActiveInterval(
                    startEpochMilliseconds: nowMs - (200 * day),
                    endEpochMilliseconds: nowMs - (195 * day)
                ),
                // Outside year window, should not affect rolling averages.
                BusyLightRuleActiveInterval(
                    startEpochMilliseconds: nowMs - (500 * day),
                    endEpochMilliseconds: nowMs - (499 * day)
                ),
            ]
        )

        let summary = metrics.summary(now: now)

        XCTAssertEqual(summary.totalActiveMilliseconds, sixHours + oneDay + fiveDays)
        XCTAssertEqual(summary.averagePerDayMilliseconds, Double(sixHours), accuracy: 0.01)
        XCTAssertEqual(summary.averagePerMonthMilliseconds, Double(sixHours + oneDay) / 30.0, accuracy: 0.01)
        XCTAssertEqual(summary.averagePerYearMilliseconds, Double(sixHours + oneDay + fiveDays) / 365.0, accuracy: 0.01)
    }

    func test_durationFormatter_usesExpectedUnitSuffixes() {
        XCTAssertTrue(BusyLightDurationFormatter.string(milliseconds: 500).hasSuffix("ms"))
        XCTAssertTrue(BusyLightDurationFormatter.string(milliseconds: 2000).hasSuffix("s"))
        XCTAssertTrue(BusyLightDurationFormatter.string(milliseconds: 120_000).hasSuffix("min"))
        XCTAssertTrue(BusyLightDurationFormatter.string(milliseconds: 7_200_000).hasSuffix("h"))
        XCTAssertTrue(BusyLightDurationFormatter.string(milliseconds: 172_800_000).hasSuffix("d"))
        XCTAssertTrue(BusyLightDurationFormatter.string(
            milliseconds: Double(Int64(2) * BusyLightRuleMetrics.monthMilliseconds)
        ).hasSuffix("mo"))
        XCTAssertTrue(BusyLightDurationFormatter.string(
            milliseconds: Double(Int64(2) * BusyLightRuleMetrics.yearMilliseconds)
        ).hasSuffix("y"))
    }

    private func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000.0)
    }
}
