import SwiftUI

enum Theme {
    static func gradient(_ a: Color, _ b: Color) -> LinearGradient {
        LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Deep plum → indigo backdrop, the "friendly night sky" look.
    static let backdrop = LinearGradient(
        colors: [Color(red: 0.24, green: 0.10, blue: 0.38), Color(red: 0.10, green: 0.12, blue: 0.32)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let accent = gradient(Color(red: 0.98, green: 0.36, blue: 0.62), Color(red: 0.55, green: 0.36, blue: 0.98))
    static let safe = gradient(Color(red: 0.20, green: 0.84, blue: 0.62), Color(red: 0.10, green: 0.62, blue: 0.86))
    static let danger = gradient(Color(red: 1.0, green: 0.42, blue: 0.36), Color(red: 0.90, green: 0.18, blue: 0.42))
}

/// Full-bleed background with a soft glow tinted per section.
struct BackdropView: View {
    var tint: Color = .pink

    var body: some View {
        ZStack {
            Theme.backdrop
            Circle()
                .fill(tint.opacity(0.35))
                .frame(width: 520, height: 520)
                .blur(radius: 140)
                .offset(x: 220, y: -180)
            Circle()
                .fill(Color.blue.opacity(0.25))
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                .offset(x: -260, y: 220)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: tint)
    }
}

struct GlassCard: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
    }
}

extension View {
    func glassCard(padding: CGFloat = 18) -> some View { modifier(GlassCard(padding: padding)) }
}

/// Big pill button with a gradient fill.
struct PillButtonStyle: ButtonStyle {
    var fill: LinearGradient = Theme.accent
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(large ? .title3.weight(.semibold) : .body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, large ? 34 : 18)
            .padding(.vertical, large ? 14 : 8)
            .background(fill, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Subtle translucent button for secondary actions.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.white.opacity(configuration.isPressed ? 0.22 : 0.12), in: Capsule())
    }
}
