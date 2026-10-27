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

struct SentrioBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [
                    SentrioVisualStyle.accent.opacity(primaryOpacity),
                    SentrioVisualStyle.secondaryAccent.opacity(secondaryOpacity),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    SentrioVisualStyle.liveAccent.opacity(tertiaryOpacity),
                    Color.clear,
                ],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 380
            )
        }
    }

    private var primaryOpacity: Double {
        reduceTransparency ? 0.055 : colorScheme == .dark ? 0.22 : 0.16
    }

    private var secondaryOpacity: Double {
        reduceTransparency ? 0.035 : colorScheme == .dark ? 0.16 : 0.11
    }

    private var tertiaryOpacity: Double {
        reduceTransparency ? 0.025 : colorScheme == .dark ? 0.12 : 0.08
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
                shape.fill(.regularMaterial)
            }
        }
        .overlay(
            shape.strokeBorder(
                Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.09),
                lineWidth: 1
            )
        )
        .shadow(
            color: Color.black.opacity(reduceTransparency ? 0 : colorScheme == .dark ? 0.18 : 0.08),
            radius: 10,
            y: 4
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
