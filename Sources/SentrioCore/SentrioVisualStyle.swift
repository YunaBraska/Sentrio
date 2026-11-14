import AppKit
import SwiftUI

enum SentrioVisualStyle {
    static let accent = Color(nsColor: .systemBlue)
    static let secondaryAccent = Color(nsColor: .systemIndigo)
    static let liveAccent = Color(nsColor: .systemTeal)
    static let panelCornerRadius: CGFloat = 14

    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [accent, secondaryAccent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct SentrioChromeBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency {
                Color(nsColor: .controlBackgroundColor)
            } else {
                Rectangle().fill(.thinMaterial)
            }

            LinearGradient(
                colors: [
                    SentrioVisualStyle.accent.opacity(0.12),
                    SentrioVisualStyle.secondaryAccent.opacity(0.05),
                    Color.clear,
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

struct SentrioCardBackground: View {
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            if reduceTransparency {
                shape.fill(Color(nsColor: .controlBackgroundColor))
            } else {
                shape.fill(.ultraThinMaterial)
            }

            shape.fill(
                LinearGradient(
                    colors: [
                        SentrioVisualStyle.accent.opacity(colorScheme == .dark ? 0.09 : 0.055),
                        SentrioVisualStyle.secondaryAccent.opacity(colorScheme == .dark ? 0.055 : 0.03),
                        Color.clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .overlay(
            shape.strokeBorder(
                Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.09),
                lineWidth: 1
            )
        )
        .shadow(
            color: Color.black.opacity(reduceTransparency ? 0 : colorScheme == .dark ? 0.12 : 0.04),
            radius: 5,
            y: 2
        )
    }
}

struct SentrioGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label
            configuration.content
        }
        .padding(10)
        .background(SentrioCardBackground(cornerRadius: SentrioVisualStyle.panelCornerRadius))
    }
}
