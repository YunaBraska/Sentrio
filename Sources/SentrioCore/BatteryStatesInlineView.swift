import SwiftUI

struct BatteryStatesInlineView: View {
    let states: [AudioDevice.BatteryState]

    var body: some View {
        let sortedStates = states.sorted(by: Self.sort)
        HStack(spacing: 6) {
            ForEach(sortedStates, id: \.self) { state in
                HStack(spacing: 2) {
                    Image(systemName: state.systemImage)
                    Text(state.shortText)
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .monospacedDigit()
    }

    static func sort(_ lhs: AudioDevice.BatteryState, _ rhs: AudioDevice.BatteryState) -> Bool {
        let order: [AudioDevice.BatteryState.Kind: Int] = [
            .left: 0,
            .right: 1,
            .device: 2,
            .other: 3,
            .case: 4,
        ]

        let l = order[lhs.kind] ?? 99
        let r = order[rhs.kind] ?? 99
        if l != r { return l < r }
        return (lhs.sourceName ?? "").localizedCaseInsensitiveCompare(rhs.sourceName ?? "") == .orderedAscending
    }
}

struct BatteryIconsInlineView: View {
    let states: [AudioDevice.BatteryState]

    var body: some View {
        let sortedStates = states.sorted(by: BatteryStatesInlineView.sort)
        HStack(spacing: 4) {
            ForEach(sortedStates, id: \.self) { state in
                Image(systemName: state.systemImage)
                    .foregroundStyle(state.level < 0.2 ? Color.red : Color.secondary.opacity(0.6))
                    .help(state.shortText)
            }
        }
        .font(.caption2)
        .monospacedDigit()
    }
}
