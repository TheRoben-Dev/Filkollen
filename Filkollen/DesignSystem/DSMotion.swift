import AppKit
import SwiftUI

extension DS {
    /// Motion tokens. "Settle, don't bounce": high damping, short responses,
    /// nothing loops unless work is happening. Every UI response stays under
    /// ~400 ms and is interruptible (springs retarget mid-flight).
    ///
    /// This is the one place that honours Reduce Motion: with it on, every
    /// token becomes a short crossfade and `transition` drops movement.
    enum Motion: CaseIterable {
        /// Press, hover, toggle, selection.
        case snappy
        /// Layout changes, expand and collapse, navigation.
        case smooth
        /// The signature scan settle only.
        case gentle

        var response: Double {
            switch self {
            case .snappy: return 0.25
            case .smooth: return 0.4
            case .gentle: return 0.6
            }
        }

        var damping: Double {
            switch self {
            case .snappy: return 0.9
            case .smooth: return 0.88
            case .gentle: return 0.82
            }
        }

        var spring: Animation { .spring(response: response, dampingFraction: damping) }

        /// The animation to use, given the user's Reduce Motion setting.
        func animation(reduceMotion: Bool) -> Animation {
            reduceMotion ? .easeInOut(duration: Duration.crossfade) : spring
        }

        /// The animation for the current system setting, for code outside a view.
        var current: Animation { animation(reduceMotion: Self.reduceMotion) }

        static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

        /// Stagger between items appearing in sequence (result tiles, list rows).
        static let stagger: Double = 0.04
        /// Most items a stagger runs over before the rest appear together.
        static let staggerLimit = 8
    }

    enum Duration {
        /// Crossfades that replace movement under Reduce Motion.
        static let crossfade: Double = 0.15
        static let fast: Double = 0.15
        static let base: Double = 0.25
        static let slow: Double = 0.4
        /// How long a toast stays before it fades.
        static let toast: Double = 6
        /// One lap of the scan ring's travelling light.
        static let sweep: Double = 1.6
    }
}

/// `withAnimation` using a motion token and the current Reduce Motion setting.
@MainActor
@discardableResult
func withMotion<Result>(_ motion: DS.Motion, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(motion.current, body)
}

extension DS {
    struct MotionModifier<V: Equatable>: ViewModifier {
        let motion: Motion
        let value: V
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func body(content: Content) -> some View {
            content.animation(motion.animation(reduceMotion: reduceMotion), value: value)
        }
    }

    struct TransitionModifier: ViewModifier {
        let transition: AnyTransition
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func body(content: Content) -> some View {
            content.transition(reduceMotion ? .opacity : transition)
        }
    }
}

extension View {
    /// `.animation(_:value:)` with a motion token; a crossfade under Reduce Motion.
    func dsAnimation<V: Equatable>(_ motion: DS.Motion, value: V) -> some View {
        modifier(DS.MotionModifier(motion: motion, value: value))
    }

    /// A transition that becomes a plain fade under Reduce Motion.
    func dsTransition(_ transition: AnyTransition) -> some View {
        modifier(DS.TransitionModifier(transition: transition))
    }
}

extension AnyTransition {
    /// Rise a little and fade in: list rows, tiles, toasts.
    static var dsRise: AnyTransition {
        .opacity.combined(with: .offset(y: DS.Space.sm))
    }

    /// Scale from slightly smaller: badges, checkmarks, the settle.
    static var dsPop: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.92))
    }
}
