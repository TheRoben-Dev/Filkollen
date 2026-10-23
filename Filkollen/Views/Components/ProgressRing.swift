import SwiftUI

/// Spinning gradient ring shown while scanning, CleanMyMac-style.
struct ScanningRing: View {
    var gradient: AngularGradient = AngularGradient(
        colors: [.pink, .purple, .blue, .teal, .pink], center: .center
    )
    var size: CGFloat = 220
    @State private var rotation: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 14)
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Scanning")
        .accessibilityAddTraits(.updatesFrequently)
        .onAppear {
            // Reduce Motion: a slow pulse-free ring instead of a spinner.
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

/// The big round call-to-action button on the home screen.
struct BigScanButton: View {
    let title: String
    let action: () -> Void
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 150, height: 150)
                    .shadow(color: .pink.opacity(0.5), radius: pulse ? 34 : 18)
                Circle()
                    .strokeBorder(.white.opacity(0.35), lineWidth: 2)
                    .frame(width: 150, height: 150)
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(pulse ? 1.03 : 1)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever()) { pulse = true }
        }
    }
}
