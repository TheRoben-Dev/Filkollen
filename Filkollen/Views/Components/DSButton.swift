import SwiftUI

/// Filkollen's button styles. Rounded rectangles like native push buttons,
/// with hover, pressed, keyboard focus, disabled and loading states.
///
/// - `.primary`: the one main action on a screen, filled with the accent.
/// - `.secondary`: everything else that's a button.
/// - `.destructive`: **only** Delete Permanently (malware, quarantine) and Empty Trash.
///   Ruby text on a ruby-tinted fill with a ruby edge.
/// - `.plain`: text-only actions inside rows and banners.
struct DSButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive, plain }
    enum Size { case regular, large }

    var kind: Kind = .secondary
    var size: Size = .regular
    var isLoading = false

    func makeBody(configuration: Configuration) -> some View {
        DSButtonBody(configuration: configuration, kind: kind, size: size, isLoading: isLoading)
    }
}

private struct DSButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: DSButtonStyle.Kind
    let size: DSButtonStyle.Size
    let isLoading: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            if isLoading {
                ProgressView().controlSize(.small)
                    .tint(foreground)
            }
            configuration.label
                .lineLimit(1)
        }
        .font(size == .large ? DS.Font.buttonLarge : DS.Font.bodyEmphasized)
        .foregroundStyle(foreground)
        .padding(kind == .plain ? EdgeInsets() : (size == .large ? DS.Inset.buttonLarge : DS.Inset.button))
        .frame(minHeight: kind == .plain ? nil : DS.Layout.minHitTarget)
        .background { background }
        .overlay {
            if kind == .secondary {
                DS.shape(DS.Radius.control).strokeBorder(DS.Color.border, lineWidth: 1)
            }
        }
        .overlay {
            // Visible focus ring for keyboard users (Full Keyboard Access).
            if isFocused && kind != .plain {
                DS.shape(DS.Radius.control + 3)
                    .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 3)
                    .padding(-3)
            }
        }
        .contentShape(DS.shape(DS.Radius.control))
        .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .dsAnimation(.snappy, value: configuration.isPressed)
        .dsAnimation(.snappy, value: hovering)
        .accessibilityAddTraits(isLoading ? .updatesFrequently : [])
    }

    private var foreground: Color {
        switch kind {
        case .primary: return DS.Color.textOnAccent
        case .destructive: return DS.Color.danger
        case .secondary: return DS.Color.textPrimary
        case .plain: return isEnabled ? .accentColor : DS.Color.textSecondary
        }
    }

    @ViewBuilder private var background: some View {
        let shape = DS.shape(DS.Radius.control)
        switch kind {
        case .primary:
            // Champagne with a soft top light and a bright hairline, like polished metal.
            shape.fill(.tint)
                .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.22), .clear, .black.opacity(0.10)],
                                                   startPoint: .top, endPoint: .bottom)))
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05)],
                                                           startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
                .overlay(shape.fill(stateOverlay))
                .shadow(color: DS.Color.brand.opacity(scheme == .dark && isEnabled ? 0.28 : 0), radius: 10, y: 2)
        case .destructive:
            // Ruby glass rather than a solid red slab: still unmistakable, never shouting.
            shape.fill(DS.Color.danger.opacity(0.16))
                .overlay(shape.strokeBorder(DS.Color.danger.opacity(0.55), lineWidth: 1))
                .overlay(shape.fill(stateOverlay))
        case .secondary:
            shape.fill(DS.Color.surfaceRaised).overlay(shape.fill(stateOverlay))
        case .plain:
            EmptyView()
        }
    }

    /// Darkens on press, lightens slightly on hover, in both themes.
    private var stateOverlay: Color {
        guard isEnabled else { return .clear }
        if configuration.isPressed { return .black.opacity(scheme == .dark ? 0.25 : 0.15) }
        if hovering { return .white.opacity(scheme == .dark ? 0.08 : 0.12) }
        return .clear
    }
}

extension ButtonStyle where Self == DSButtonStyle {
    static var dsPrimary: DSButtonStyle { DSButtonStyle(kind: .primary) }
    static var dsSecondary: DSButtonStyle { DSButtonStyle(kind: .secondary) }
    static var dsDestructive: DSButtonStyle { DSButtonStyle(kind: .destructive) }
    static var dsPlain: DSButtonStyle { DSButtonStyle(kind: .plain) }

    static func ds(_ kind: DSButtonStyle.Kind, size: DSButtonStyle.Size = .regular, loading: Bool = false) -> DSButtonStyle {
        DSButtonStyle(kind: kind, size: size, isLoading: loading)
    }
}

/// An icon-only button with a tooltip, a hover backplate and a VoiceOver label.
struct DSIconButton: View {
    let symbol: String
    let label: String
    var role: ButtonRole?
    let action: () -> Void

    init(_ label: String, symbol: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.label = label
        self.symbol = symbol
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .frame(width: DS.Layout.minHitTarget, height: DS.Layout.minHitTarget)
        }
        .buttonStyle(DSIconButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct DSIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconBody(configuration: configuration)
    }

    private struct IconBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(hovering && isEnabled ? DS.Color.textPrimary : DS.Color.textSecondary)
                .background {
                    DS.shape(DS.Radius.small)
                        .fill(configuration.isPressed ? DS.Color.surfaceSunken : (hovering ? DS.Color.surfaceRaised : .clear))
                }
                .overlay {
                    if isFocused {
                        DS.shape(DS.Radius.small).strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 2)
                    }
                }
                .contentShape(DS.shape(DS.Radius.small))
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
                .dsAnimation(.snappy, value: hovering)
        }
    }
}
