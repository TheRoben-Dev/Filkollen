import AppKit
import SwiftUI

extension View {
    /// Paints the hosting window's title bar and toolbar area with the canvas
    /// colour, so the window reads as one onyx surface instead of a grey system
    /// title bar above a dark page.
    func dsWindowChrome() -> some View {
        background(DSWindowChrome())
    }
}

private struct DSWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ChromeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DS.styleChrome(of: window)
        }
    }
}

extension DS {
    /// The canvas colour on a window's background and a transparent title bar.
    @MainActor static func styleChrome(of window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(named: "DesignSystem/Canvas", bundle: .main) ?? .windowBackgroundColor
    }
}
