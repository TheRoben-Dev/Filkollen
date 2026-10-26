import AppKit

/// The standard About panel, with the version, build and a short privacy note.
enum AboutPanel {
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    @MainActor static func show() {
        let credits = NSMutableAttributedString(
            string: "Finds and removes junk, leftovers and duplicates, and checks for known malware.\n\n"
                + "Everything is checked on your Mac. Filkollen sends no telemetry; its only network use is downloading the MalwareBazaar threat list (and its own updates, when enabled).",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor]
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        credits.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: credits.length))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        // The standard panel is grey; give it the canvas like every other window.
        Task { @MainActor in
            if let panel = NSApp.keyWindow, panel is NSPanel { DS.styleChrome(of: panel) }
        }
    }
}
