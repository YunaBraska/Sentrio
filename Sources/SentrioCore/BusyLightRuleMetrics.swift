import Foundation

struct BusyLightRuleActiveInterval: Codable, Equatable {
    var startEpochMilliseconds: Int64
    var endEpochMilliseconds: Int64

    var durationMilliseconds: Int64 {
        max(endEpochMilliseconds - startEpochMilliseconds, 0)
    }

    func overlapDuration(in window: ClosedRange<Int64>) -> Int64 {
        let start = max(startEpochMilliseconds, window.lowerBound)
        let end = min(endEpochMilliseconds, window.upperBound)
        return max(end - start, 0)
    }
}

struct BusyLightRuleMetrics: Codable, Equatable {
    static let dayMilliseconds: Int64 = 86_400_000
    static let monthMilliseconds: Int64 = 30 * dayMilliseconds
    static let yearMilliseconds: Int64 = 365 * dayMilliseconds

    var totalActiveMilliseconds: Int64
    var recentIntervals: [BusyLightRuleActiveInterval]

    init(
        totalActiveMilliseconds: Int64 = 0,
        recentIntervals: [BusyLightRuleActiveInterval] = []
    ) {
        self.totalActiveMilliseconds = max(totalActiveMilliseconds, 0)
        self.recentIntervals = recentIntervals
    }

    mutating func recordInterval(start: Date, end: Date, now: Date = Date()) {
        let startMs = start.epochMilliseconds
        let endMs = end.epochMilliseconds
        guard endMs > startMs else { return }

        let interval = BusyLightRuleActiveInterval(
            startEpochMilliseconds: startMs,
            endEpochMilliseconds: endMs
        )
        totalActiveMilliseconds += interval.durationMilliseconds
        recentIntervals.append(interval)
        pruneRecentIntervals(now: now)
    }

    mutating func pruneRecentIntervals(now: Date = Date()) {
        let cutoff = now.epochMilliseconds - Self.yearMilliseconds
        recentIntervals.removeAll { $0.endEpochMilliseconds < cutoff }
    }

    func activeMilliseconds(inLast windowMilliseconds: Int64, now: Date) -> Int64 {
        guard windowMilliseconds > 0 else { return 0 }
        let nowMs = now.epochMilliseconds
        let window = (nowMs - windowMilliseconds) ... nowMs
        return recentIntervals.reduce(into: Int64(0)) { partialResult, interval in
            partialResult += interval.overlapDuration(in: window)
        }
    }

    func summary(now: Date = Date()) -> BusyLightRuleMetricsSummary {
        let dayTotal = Double(activeMilliseconds(inLast: Self.dayMilliseconds, now: now))
        let monthTotal = Double(activeMilliseconds(inLast: Self.monthMilliseconds, now: now))
        let yearTotal = Double(activeMilliseconds(inLast: Self.yearMilliseconds, now: now))

        return BusyLightRuleMetricsSummary(
            totalActiveMilliseconds: totalActiveMilliseconds,
            averagePerDayMilliseconds: dayTotal,
            averagePerMonthMilliseconds: monthTotal / 30.0,
            averagePerYearMilliseconds: yearTotal / 365.0
        )
    }
}

struct BusyLightRuleMetricsSummary: Equatable {
    var totalActiveMilliseconds: Int64
    var averagePerDayMilliseconds: Double
    var averagePerMonthMilliseconds: Double
    var averagePerYearMilliseconds: Double
}

enum BusyLightDurationFormatter {
    static func string(milliseconds: Double) -> String {
        let ms = max(milliseconds, 0)

        if ms < 1000 {
            return "\(formatted(ms))ms"
        }
        if ms < 60000 {
            return "\(formatted(ms / 1000))s"
        }
        if ms < 3_600_000 {
            return "\(formatted(ms / 60000))min"
        }
        if ms < BusyLightRuleMetrics.dayMilliseconds.doubleValue {
            return "\(formatted(ms / 3_600_000))h"
        }
        if ms < BusyLightRuleMetrics.monthMilliseconds.doubleValue {
            return "\(formatted(ms / BusyLightRuleMetrics.dayMilliseconds.doubleValue))d"
        }
        if ms < BusyLightRuleMetrics.yearMilliseconds.doubleValue {
            return "\(formatted(ms / BusyLightRuleMetrics.monthMilliseconds.doubleValue))mo"
        }
        return "\(formatted(ms / BusyLightRuleMetrics.yearMilliseconds.doubleValue))y"
    }

    private static func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... 1)))
    }
}

private extension Date {
    var epochMilliseconds: Int64 {
        Int64(timeIntervalSince1970 * 1000)
    }
}

private extension Int64 {
    var doubleValue: Double {
        Double(self)
    }
}
