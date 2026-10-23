import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            CleanupSettings().tabItem { Label("Cleanup", systemImage: "sparkles") }
            ProtectionSettings().tabItem { Label("Protection", systemImage: "shield.lefthalf.filled") }
            UpdatesSettings().tabItem { Label("Updates", systemImage: "arrow.down.app") }
        }
        .frame(width: 520)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(Pref.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(Pref.keepRunningInMenuBar) private var keepRunning = true
    @AppStorage(Pref.alwaysStartHidden) private var startHidden = false
    @AppStorage(Pref.notificationsEnabled) private var notifications = true
    @AppStorage(Pref.autoScanHours) private var autoScanHours = 24

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var needsApproval = LoginItem.needsApproval
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open Filkollen at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        guard enabled != LoginItem.isEnabled else { return }
                        do {
                            try LoginItem.set(enabled)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LoginItem.isEnabled
                        }
                        needsApproval = LoginItem.needsApproval
                    }
                if needsApproval {
                    HStack {
                        Text("macOS needs you to allow Filkollen in Login Items.")
                            .font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button("Open Login Items") { LoginItem.openSystemSettings() }
                    }
                }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Text("When opened at login, Filkollen starts quietly in the menu bar with no window.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Menu bar") {
                Toggle("Show Filkollen in the menu bar", isOn: $showMenuBarIcon)
                Toggle("Keep running in the menu bar when the window is closed", isOn: $keepRunning)
                    .disabled(!showMenuBarIcon)
                Toggle("Always start hidden (menu bar only)", isOn: $startHidden)
                    .disabled(!showMenuBarIcon || !keepRunning)
            }

            Section("Background") {
                Picker("Automatic Smart Scan", selection: $autoScanHours) {
                    Text("Off").tag(0)
                    Text("Every 6 hours").tag(6)
                    Text("Every 12 hours").tag(12)
                    Text("Daily").tag(24)
                    Text("Weekly").tag(168)
                }
                Toggle("Notify me about junk, threats and updates", isOn: $notifications)
                    .onChange(of: notifications) { if $0 { Notifier.requestPermission() } }
                Text("Background scans only look; nothing is cleaned without your review.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Permissions") {
                LabeledContent("Full Disk Access") {
                    HStack {
                        Text(model.hasFullDiskAccess ? "Granted" : "Not granted")
                            .foregroundStyle(model.hasFullDiskAccess ? .green : .orange)
                        Button("Open Settings") { FullDiskAccess.openSettings() }
                    }
                }
                Button("Show Onboarding Again") {
                    UserDefaults.standard.set(false, forKey: "onboardingDismissed")
                    model.onboardingDismissed = false
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 560)
        .onAppear {
            launchAtLogin = LoginItem.isEnabled
            needsApproval = LoginItem.needsApproval
        }
    }
}

// MARK: - Cleanup

private struct CleanupSettings: View {
    @AppStorage(Pref.tempMinAgeDays) private var tempMinAgeDays = 3
    @AppStorage(Pref.largeFileMB) private var largeFileMB = 500
    @AppStorage(Pref.oldFileMonths) private var oldFileMonths = 12
    @AppStorage(Pref.leftoverPlainNames) private var leftoverPlainNames = false
    @AppStorage(Pref.excludedPaths) private var excludedPaths = ""

    var body: some View {
        Form {
            Section("System Junk") {
                Stepper("Only remove temporary files older than \(tempMinAgeDays) day\(tempMinAgeDays == 1 ? "" : "s")",
                        value: $tempMinAgeDays, in: 1...60)
            }
            Section("App Leftovers") {
                Toggle("Also look for folders named after removed apps", isOn: $leftoverPlainNames)
                Text("Finds folders like Application Support › Spotify. Matches that can't be confirmed are marked Low confidence and never pre-selected.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Large & Old Files") {
                Picker("Show files larger than", selection: $largeFileMB) {
                    Text("100 MB").tag(100)
                    Text("250 MB").tag(250)
                    Text("500 MB").tag(500)
                    Text("1 GB").tag(1000)
                    Text("2 GB").tag(2000)
                }
                Picker("Also show files not opened for", selection: $oldFileMonths) {
                    Text("Off").tag(0)
                    Text("6 months").tag(6)
                    Text("1 year").tag(12)
                    Text("2 years").tag(24)
                }
                Text("Old files are only listed from 50 MB up.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                TextEditor(text: $excludedPaths)
                    .font(.body.monospaced())
                    .frame(height: 140)
                HStack {
                    Text("One folder per line. Scans skip these and everything inside them.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Add Folder…", action: addFolder)
                }
            } header: {
                Text("Never touch these folders")
            }
        }
        .formStyle(.grouped)
        .frame(height: 440)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Exclude"
        guard panel.runModal() == .OK else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let added = panel.urls.map { url -> String in
            let path = url.path
            return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
        }
        var lines = excludedPaths.split(whereSeparator: \.isNewline).map(String.init)
        lines += added.filter { !lines.contains($0) }
        excludedPaths = lines.joined(separator: "\n")
    }
}

// MARK: - Protection

private struct ProtectionSettings: View {
    @EnvironmentObject private var protection: ProtectionModel
    @AppStorage("abuseChAuthKey") private var abuseChAuthKey = ""
    @AppStorage(Pref.autoUpdateThreatDB) private var autoUpdate = true

    var body: some View {
        Form {
            Section("Threat database") {
                LabeledContent("Known threats", value: "\(protection.databaseCount.formatted()) hashes")
                LabeledContent("Last updated") {
                    Text(protection.databaseUpdated.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
                }
                SecureField("abuse.ch Auth-Key", text: $abuseChAuthKey)
                Link("Get a free Auth-Key at auth.abuse.ch", destination: URL(string: "https://auth.abuse.ch/")!)
                    .font(.caption)
                Toggle("Update automatically in the background (weekly)", isOn: $autoUpdate)
                HStack {
                    Button("Update Now") { protection.updateDatabase() }
                        .disabled(protection.isBusy || abuseChAuthKey.isEmpty)
                    if protection.phase == .updating {
                        ProgressView().controlSize(.small)
                        Text(protection.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if let error = protection.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Scanning") {
                Toggle("Also scan with ClamAV when installed", isOn: $protection.useClamAV)
                    .disabled(!protection.clamAVInstalled)
                if !protection.clamAVInstalled {
                    Text("Install ClamAV with Homebrew (brew install clamav) for a second opinion.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Open Quarantine Folder") { NSWorkspace.shared.open(Quarantine.directory) }
            }
        }
        .formStyle(.grouped)
        .frame(height: 440)
    }
}

// MARK: - Updates

private struct UpdatesSettings: View {
    @EnvironmentObject private var updates: UpdatesModel
    @AppStorage(Pref.checkSparkle) private var checkSparkle = true
    @AppStorage(Pref.checkHomebrew) private var checkHomebrew = true
    @AppStorage(Pref.checkAppStore) private var checkAppStore = true
    @AppStorage(Pref.checkMacOS) private var checkMacOS = true
    @AppStorage(Pref.brewUpdateFirst) private var brewUpdateFirst = true
    @AppStorage(Pref.autoCheckUpdates) private var autoCheck = true

    var body: some View {
        Form {
            Section("Check for updates from") {
                Toggle("Apps that update themselves (Sparkle)", isOn: $checkSparkle)
                Toggle(isOn: $checkHomebrew) {
                    Text("Homebrew formulae and casks")
                    if !updates.brewInstalled { Text("Homebrew isn't installed").foregroundStyle(.orange) }
                }
                Toggle("Refresh Homebrew's package list first (brew update)", isOn: $brewUpdateFirst)
                    .disabled(!checkHomebrew)
                Toggle(isOn: $checkAppStore) {
                    Text("Mac App Store")
                    if !updates.masInstalled { Text("Needs mas: brew install mas").foregroundStyle(.orange) }
                }
                Toggle("macOS software updates", isOn: $checkMacOS)
            }
            Section("Schedule") {
                Toggle("Check daily in the background and notify me", isOn: $autoCheck)
                LabeledContent("Last checked") {
                    Text(updates.lastChecked.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 400)
    }
}
