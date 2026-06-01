import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = VaultSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Welcome to Font Vault")
                .font(.largeTitle.bold())

            Text("Font Vault catalogs fonts in a vault folder on your Mac. Choose whether Font Vault manages those files for you, or you manage them in Finder. If you already use FontExplorer X, you can point the vault at your existing ~/Documents/FEX folder — Font Vault uses its own catalog, not .fexdb. Use Typeface or FontBase for preview and activation.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox("Vault location") {
                VStack(alignment: .leading, spacing: 12) {
                    Button("Use default folder (~/Documents/FontVault)") {
                        settings.useDefaultVaultLocation()
                    }

                    Button("Use my existing FontExplorer folder (~/Documents/FEX)…") {
                        settings.vaultRootURL = FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent("Documents/FEX", isDirectory: true)
                    }

                    Button("Choose another folder…") {
                        appState.pickVaultFolder()
                    }

                    if let url = settings.vaultRootURL {
                        Text(url.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Who manages font files?") {
                Toggle(VaultOrganizationHelp.toggleTitle, isOn: $settings.organizesVaultFiles)
                Text(settings.vaultOrganizationExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Continue") {
                    guard let url = settings.vaultRootURL else { return }
                    appState.completeOnboarding(vaultURL: url)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(settings.vaultRootURL == nil)
            }
        }
        .padding(32)
        .frame(width: 520)
    }
}
