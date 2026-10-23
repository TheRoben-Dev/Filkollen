import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var protection: ProtectionModel
    @AppStorage("abuseChAuthKey") private var abuseChAuthKey = ""

    var body: some View {
        Form {
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
            Section("Protection") {
                LabeledContent("Threat database", value: "\(protection.databaseCount.formatted()) hashes")
                SecureField("abuse.ch Auth-Key (optional)", text: $abuseChAuthKey)
                Link("Get a free Auth-Key at auth.abuse.ch", destination: URL(string: "https://auth.abuse.ch/")!)
                    .font(.caption)
                Toggle("Also scan with ClamAV when installed", isOn: $protection.useClamAV)
                    .disabled(!protection.clamAVInstalled)
                Button("Open Quarantine Folder") { NSWorkspace.shared.open(Quarantine.directory) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
    }
}
