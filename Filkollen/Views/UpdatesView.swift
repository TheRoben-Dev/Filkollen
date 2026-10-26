import SwiftUI

struct UpdatesView: View {
    @EnvironmentObject private var updates: UpdatesModel
    @AppStorage(Pref.checkHomebrew) private var checkHomebrew = true
    @AppStorage(Pref.checkAppStore) private var checkAppStore = true

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(DS.Inset.page)

            if let message = updates.message {
                DSBanner(.info, title: message)
                    .padding(.horizontal, DS.Space.xxl).padding(.bottom, DS.Space.md)
            }

            ScrollView {
                VStack(spacing: DS.Space.md) {
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
                .padding(.horizontal, DS.Space.xxl).padding(.bottom, DS.Space.xxl)
            }
        }
    }

    private var header: some View {
        DSPageHeader(title: String(localized: "App Updates"), subtitle: subtitle,
                     tile: DSTile(symbol: "arrow.down.app.fill", tint: DS.Color.info, size: .large)) {
            Button {
                updates.check()
            } label: {
                Label(updates.isChecking ? "Checking…" : "Check for Updates", systemImage: DS.Icon.refresh)
            }
            .buttonStyle(.ds(.primary, loading: updates.isChecking))
            .disabled(updates.isChecking)
        }
    }

    private var subtitle: String {
        guard let last = updates.lastChecked else { return String(localized: "Apps, Homebrew, App Store and macOS in one place") }
        return String(localized: "Last checked \(last.formatted(.relative(presentation: .named)))")
    }

    // MARK: Sections

    @ViewBuilder private func sourceSection(_ source: AppUpdate.Source) -> some View {
        let list = updates.updates(for: source)
        let checking = updates.checkingSources.contains(source)
        if !list.isEmpty || checking {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                HStack(spacing: DS.Space.sm) {
                    Label(source.rawValue, systemImage: source.symbol).font(DS.Font.headline).foregroundStyle(DS.Color.textPrimary)
                    if checking { ProgressView().controlSize(.small).padding(.leading, DS.Space.xs) }
                    Spacer()
                    if source == .homebrew, list.count > 1 {
                        Button("Update All") { updates.upgradeHomebrew(list) }
                            .buttonStyle(.dsSecondary)
                            .disabled(!updates.working.isDisjoint(with: list.map(\.id)))
                    }
                    if source == .appStore, !list.isEmpty {
                        Button("Open App Store") { NSWorkspace.shared.open(AppStoreChecker.updatesPage) }
                            .buttonStyle(.dsSecondary)
                    }
                }
                ForEach(list) { update in
                    if update.id != list.first?.id { Divider() }
                    UpdateRow(update: update, working: updates.working.contains(update.id)) {
                        updates.perform(update)
                    }
                }
                if checking && list.isEmpty {
                    Text(source == .macOS ? "Asking Software Update… this can take a minute."
                                          : "Checking…")
                        .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                }
            }
            .dsCard()
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
        DSBanner(kind: .info, title: text) {
            Link(link, destination: URL(string: url)!).font(DS.Font.callout.weight(.semibold)).foregroundStyle(DS.Color.brand)
        }
    }

    private var placeholder: some View {
        DSEmptyState(symbol: "arrow.down.app", tint: DS.Color.info,
                     title: String(localized: "Find out what's out of date"),
                     message: String(localized: "Filkollen checks apps that update themselves (Sparkle), Homebrew formulae and casks, the Mac App Store and macOS itself.")) {
            Button("Check for Updates") { updates.check() }
                .buttonStyle(.ds(.primary, size: .large))
        }
    }

    private var upToDate: some View {
        DSEmptyState(symbol: "checkmark.seal.fill", tint: DS.Color.success,
                     title: String(localized: "Everything is up to date"))
    }
}

private struct UpdateRow: View {
    let update: AppUpdate
    let working: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.md) {
            icon
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(update.name).font(DS.Font.bodyEmphasized).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                HStack(spacing: DS.Space.xs) {
                    Text(update.installed)
                    Image(systemName: "arrow.right").font(DS.Font.badge).accessibilityLabel(String(localized: "to"))
                    Text(update.available).foregroundStyle(DS.Color.success)
                    if update.isCask { Text("· cask").foregroundStyle(DS.Color.textTertiary) }
                }
                .font(DS.Font.numericCaption)
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(1)
            }
            Spacer()
            if let info = update.infoURL {
                Link(destination: info) { Image(systemName: "doc.text") }.foregroundStyle(DS.Color.brand)
                    .help("Release notes")
                    .accessibilityLabel(String(localized: "Release notes for \(update.name)"))
                    .foregroundStyle(DS.Color.textSecondary)
            }
            Button(actionTitle, action: action)
                .buttonStyle(.ds(.secondary, loading: working))
                .disabled(working)
        }
        .padding(.vertical, DS.Space.xxs)
    }

    @ViewBuilder private var icon: some View {
        if let url = update.appURL {
            DSFileIcon(url: url, size: DS.Icon.TileSize.medium.side)
        } else {
            DSTile(symbol: update.source.symbol, tint: DS.Color.info, size: .medium)
        }
    }

    private var actionTitle: String {
        switch update.source {
        case .apps: return String(localized: "Open")
        case .homebrew: return String(localized: "Update")
        case .appStore: return String(localized: "App Store")
        case .macOS: return String(localized: "Install…")
        }
    }
}
