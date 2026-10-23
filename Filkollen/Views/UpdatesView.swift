import SwiftUI

struct UpdatesView: View {
    @EnvironmentObject private var updates: UpdatesModel
    @AppStorage(Pref.checkHomebrew) private var checkHomebrew = true
    @AppStorage(Pref.checkAppStore) private var checkAppStore = true

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 18)

            if let message = updates.message {
                Text(message)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(padding: 12)
                    .padding(.horizontal, 28).padding(.bottom, 12)
            }

            ScrollView {
                VStack(spacing: 14) {
                    hints
                    if updates.lastChecked == nil && !updates.isChecking {
                        placeholder
                    } else if updates.updates.isEmpty && !updates.isChecking {
                        upToDate
                    } else {
                        ForEach(AppUpdate.Source.allCases, id: \.self) { source in
                            sourceSection(source)
                        }
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 28)
            }
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 16) {
            GradientIcon(symbol: "arrow.down.app.fill", gradient: Theme.gradient(.cyan, .blue), size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("App Updates").font(.system(size: 26, weight: .bold, design: .rounded))
                Text(subtitle).foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            Button {
                updates.check()
            } label: {
                if updates.isChecking {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking…") }
                } else {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(PillButtonStyle(fill: Theme.gradient(.cyan, .blue)))
            .disabled(updates.isChecking)
        }
    }

    private var subtitle: String {
        guard let last = updates.lastChecked else { return "Apps, Homebrew, App Store and macOS in one place" }
        return "Last checked \(last.formatted(.relative(presentation: .named)))"
    }

    // MARK: Sections

    @ViewBuilder private func sourceSection(_ source: AppUpdate.Source) -> some View {
        let list = updates.updates(for: source)
        let checking = updates.checkingSources.contains(source)
        if !list.isEmpty || checking {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(source.rawValue, systemImage: source.symbol).font(.headline)
                    if checking { ProgressView().controlSize(.small).padding(.leading, 4) }
                    Spacer()
                    if source == .homebrew, list.count > 1 {
                        Button("Update All") { updates.upgradeHomebrew(list) }
                            .buttonStyle(GhostButtonStyle())
                            .disabled(!updates.working.isDisjoint(with: list.map(\.id)))
                    }
                    if source == .appStore, !list.isEmpty {
                        Button("Open App Store") { NSWorkspace.shared.open(AppStoreChecker.updatesPage) }
                            .buttonStyle(GhostButtonStyle())
                    }
                }
                ForEach(list) { update in
                    UpdateRow(update: update, working: updates.working.contains(update.id)) {
                        updates.perform(update)
                    }
                }
                if checking && list.isEmpty {
                    Text(source == .macOS ? "Asking Software Update… this can take a minute."
                                          : "Checking…")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                }
            }
            .glassCard()
        }
    }

    @ViewBuilder private var hints: some View {
        if checkHomebrew && !updates.brewInstalled {
            hint("Homebrew isn't installed, so command-line tools and casks are skipped.",
                 link: "Get Homebrew", url: "https://brew.sh")
        }
        if checkAppStore && !updates.masInstalled {
            hint("To list App Store updates, install the free mas tool: brew install mas",
                 link: "About mas", url: "https://github.com/mas-cli/mas")
        }
    }

    private func hint(_ text: String, link: String, url: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(.cyan)
            Text(text).font(.callout)
            Spacer()
            Link(link, destination: URL(string: url)!).font(.callout.weight(.semibold))
        }
        .glassCard(padding: 12)
    }

    private var placeholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.app").font(.system(size: 54)).foregroundStyle(.white.opacity(0.5))
            Text("Find out what's out of date").font(.title3.weight(.semibold))
            Text("Filkollen checks apps that update themselves (Sparkle), Homebrew formulae and casks, the Mac App Store and macOS itself.")
                .multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.65)).frame(maxWidth: 440)
            Button("Check for Updates") { updates.check() }
                .buttonStyle(PillButtonStyle(fill: Theme.gradient(.cyan, .blue), large: true))
                .padding(.top, 6)
        }
        .padding(.top, 50)
    }

    private var upToDate: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(Theme.safe)
            Text("Everything is up to date").font(.title3.weight(.semibold))
        }
        .padding(.top, 60)
    }
}

private struct UpdateRow: View {
    let update: AppUpdate
    let working: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(update.name).font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 4) {
                    Text(update.installed)
                    Image(systemName: "arrow.right").font(.caption2)
                    Text(update.available).foregroundStyle(.green)
                    if update.isCask { Text("· cask").foregroundStyle(.white.opacity(0.5)) }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
            }
            Spacer()
            if let info = update.infoURL {
                Link(destination: info) { Image(systemName: "doc.text") }
                    .help("Release notes")
                    .foregroundStyle(.white.opacity(0.7))
            }
            if working {
                ProgressView().controlSize(.small).frame(width: 90)
            } else {
                Button(actionTitle, action: action).buttonStyle(GhostButtonStyle())
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var icon: some View {
        if let url = update.appURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().frame(width: 34, height: 34)
        } else {
            GradientIcon(symbol: update.source.symbol, gradient: Theme.gradient(.cyan, .blue), size: 34)
        }
    }

    private var actionTitle: String {
        switch update.source {
        case .apps: return "Open"
        case .homebrew: return "Update"
        case .appStore: return "App Store"
        case .macOS: return "Install…"
        }
    }
}
