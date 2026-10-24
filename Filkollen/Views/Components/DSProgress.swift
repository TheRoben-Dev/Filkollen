import AppKit
import SwiftUI

// MARK: - Counting numbers

/// A byte count that counts to its new value instead of jumping. Monospaced
/// digits keep the width steady; VoiceOver hears only the final value.
struct DSByteCount: View, Animatable {
    /// Interpolated by SwiftUI while animating.
    var animatableData: Double
    let target: Int64
    var font: Font = DS.Font.display

    init(_ bytes: Int64, font: Font = DS.Font.display) {
        animatableData = Double(bytes)
        target = bytes
        self.font = font
    }

    var body: some View {
        Text(Int64(animatableData.rounded()).formattedBytes)
            .font(font)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityLabel(Text(target.formattedBytes))
    }
}

/// An integer count (items, threats) that counts like `DSByteCount`.
struct DSCount: View, Animatable {
    var animatableData: Double
    let target: Int
    var font: Font = DS.Font.numericMedium

    init(_ value: Int, font: Font = DS.Font.numericMedium) {
        animatableData = Double(value)
        target = value
        self.font = font
    }

    var body: some View {
        Text(Int(animatableData.rounded()).formatted())
            .font(font)
            .monospacedDigit()
            .accessibilityLabel(Text(target.formatted()))
    }
}

// MARK: - Signature scan ring

/// The signature scan ring. One segment per category in its family tint,
/// filling as each scanner really finishes (no fake progress). While work is
/// running a soft light travels along the unfinished track. When `settled`
/// turns true the segments close into one brand-coloured ring that settles
/// with a single gentle spring and a haptic tick.
struct DSScanRing<Center: View>: View {
    typealias Segment = DSScanSegment

    var segments: [Segment]
    var isWorking: Bool
    var settled: Bool
    var diameter: CGFloat = 240
    var lineWidth: CGFloat = 14
    /// What VoiceOver says instead of the scan progress, for other kinds of work (cleaning, malware scan).
    var label: String? = nil
    @ViewBuilder var center: Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var gap: Double { settled || segments.count < 2 ? 0 : 0.012 }

    var body: some View {
        ZStack {
            ZStack {
                Circle().stroke(DS.Color.surfaceSunken, lineWidth: lineWidth)

                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    let span = 1 / Double(max(segments.count, 1))
                    let start = Double(index) * span + gap / 2
                    let end = start + (span - gap) * min(max(segment.progress, 0), 1)
                    Circle()
                        .trim(from: start, to: max(start, end))
                        .stroke(settled ? DS.Color.brand : segment.tint,
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: settled ? .butt : .round))
                }

                if isWorking && !settled && !reduceMotion {
                    Sweep(lineWidth: lineWidth)
                }
            }
            .rotationEffect(.degrees(-90))
            .accessibilityHidden(true)

            center
        }
        .frame(width: diameter, height: diameter)
        .modifier(SettleEffect(trigger: settled))
        .dsAnimation(.smooth, value: segments)
        .dsAnimation(.gentle, value: settled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isWorking ? .updatesFrequently : [])
    }

    private var accessibilityText: String {
        if let label { return label }
        let done = segments.filter { $0.progress >= 1 }.count
        return isWorking
            ? String(localized: "Scanning, \(done) of \(segments.count) done")
            : String(localized: "Scan complete")
    }
}

/// One category's share of the scan ring.
struct DSScanSegment: Identifiable, Equatable {
    let id: String
    var tint: Color
    /// 0 = not done, 1 = done. Values in between are allowed if a scanner reports them.
    var progress: Double

    /// Ring segments for categories, filled when the category has a result and isn't still scanning.
    static func segments(for categories: [JunkCategory], scanning: Set<JunkCategory>, finished: Set<JunkCategory>) -> [DSScanSegment] {
        categories.map { category in
            DSScanSegment(id: category.rawValue, tint: category.dsTint,
                    progress: finished.contains(category) && !scanning.contains(category) ? 1 : 0)
        }
    }
}

/// The travelling light: a short arc with a fading tail, one lap per `DS.Duration.sweep`.
private struct Sweep: View {
    let lineWidth: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = t.truncatingRemainder(dividingBy: DS.Duration.sweep) / DS.Duration.sweep
            Circle()
                .trim(from: 0, to: 0.16)
                .stroke(
                    AngularGradient(colors: [DS.Color.brand.opacity(0), DS.Color.brand.opacity(0.85)],
                                    center: .center, startAngle: .degrees(0), endAngle: .degrees(0.16 * 360)),
                    style: StrokeStyle(lineWidth: lineWidth * 0.6, lineCap: .round)
                )
                .rotationEffect(.degrees(phase * 360))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The settle: a small swell and rest. keyframeAnimator on macOS 14+, a spring
/// pair on macOS 13; nothing under Reduce Motion. Plays a haptic tick on
/// trackpads that support it.
private struct SettleEffect: ViewModifier {
    let trigger: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bumped once per settle, so un-settling (a new scan) doesn't play it.
    @State private var settles = 0
    @State private var swell = false

    func body(content: Content) -> some View {
        Group {
            if #available(macOS 14.0, *), !reduceMotion {
                content.keyframeAnimator(initialValue: 1.0, trigger: settles) { view, scale in
                    view.scaleEffect(scale)
                } keyframes: { _ in
                    KeyframeTrack(\.self) {
                        SpringKeyframe(1.045, duration: 0.22, spring: .snappy)
                        SpringKeyframe(0.985, duration: 0.2, spring: .smooth)
                        SpringKeyframe(1.0, duration: 0.3, spring: .smooth)
                    }
                }
            } else {
                content.scaleEffect(swell ? 1.04 : 1)
            }
        }
        .onChange(of: trigger) { settled in
            guard settled else { return }
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            guard !reduceMotion else { return }
            settles += 1
            if #unavailable(macOS 14.0) {
                withAnimation(DS.Motion.snappy.spring) { swell = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + DS.Duration.base) {
                    withAnimation(DS.Motion.gentle.spring) { swell = false }
                }
            }
        }
    }
}

// MARK: - Linear progress

/// A thin bar: determinate with a value, a gently moving sweep without one.
struct DSLinearProgress: View {
    var value: Double?
    var tint: Color = .accentColor
    var height: CGFloat = DS.Space.xs + 2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(DS.Color.surfaceSunken)
                if let value {
                    Capsule().fill(tint)
                        .frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
                        .dsAnimation(.smooth, value: value)
                } else if reduceMotion {
                    Capsule().fill(tint.opacity(0.5))
                } else {
                    TimelineView(.animation) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: DS.Duration.sweep) / DS.Duration.sweep
                        Capsule().fill(tint)
                            .frame(width: geo.size.width * 0.3)
                            .offset(x: (geo.size.width * 1.3) * phase - geo.size.width * 0.3)
                    }
                    .clipShape(Capsule())
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Progress"))
        .accessibilityValue(value.map { Text($0, format: .percent.precision(.fractionLength(0))) } ?? Text("In progress"))
    }
}

// MARK: - Placeholder shimmer

/// A soft highlight that passes over placeholder shapes while content loads.
/// Static under Reduce Motion.
struct DSShimmer: ViewModifier {
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.overlay {
                TimelineView(.animation) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: DS.Duration.sweep) / DS.Duration.sweep
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.14), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.5)
                            .offset(x: geo.size.width * 1.5 * phase - geo.size.width * 0.5)
                    }
                }
                .mask(content)
                .allowsHitTesting(false)
            }
        } else {
            content
        }
    }
}

extension View {
    func dsShimmer(_ active: Bool = true) -> some View { modifier(DSShimmer(active: active)) }
}

/// A grey stand-in for a list row while it loads.
struct DSPlaceholderRow: View {
    var body: some View {
        HStack(spacing: DS.Space.md) {
            DS.shape(DS.Radius.small).fill(DS.Color.surfaceSunken).frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                DS.shape(DS.Radius.badge).fill(DS.Color.surfaceSunken).frame(width: 180, height: 10)
                DS.shape(DS.Radius.badge).fill(DS.Color.surfaceSunken).frame(width: 260, height: 8)
            }
            Spacer()
            DS.shape(DS.Radius.badge).fill(DS.Color.surfaceSunken).frame(width: 56, height: 10)
        }
        .padding(DS.Inset.row)
        .dsShimmer()
        .accessibilityHidden(true)
    }
}
