import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = VaultSettings.shared

    var body: some View {
        TabView(selection: $appState.settingsTab) {
            GeneralSettingsTab()
                .tabItem { Label(SettingsTab.general.title, systemImage: SettingsTab.general.systemImage) }
                .tag(SettingsTab.general)

            FontTableSettingsTab()
                .tabItem { Label(SettingsTab.fontTable.title, systemImage: SettingsTab.fontTable.systemImage) }
                .tag(SettingsTab.fontTable)

            InspectorSettingsTab()
                .tabItem { Label(SettingsTab.inspector.title, systemImage: SettingsTab.inspector.systemImage) }
                .tag(SettingsTab.inspector)

            VaultSettingsTab()
                .tabItem { Label(SettingsTab.vault.title, systemImage: SettingsTab.vault.systemImage) }
                .tag(SettingsTab.vault)
        }
        .frame(minWidth: 560, minHeight: 440)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = VaultSettings.shared

    private func formatBinding(_ keyPath: WritableKeyPath<ImportFormatOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings.importFormats[keyPath: keyPath] },
            set: { newValue in
                var formats = settings.importFormats
                formats[keyPath: keyPath] = newValue
                settings.importFormats = formats
            }
        )
    }

    var body: some View {
        Form {
            Section("Vault folder") {
                if let url = settings.vaultRootURL {
                    Text(url.path)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                } else {
                    Text("Not configured")
                        .foregroundStyle(.secondary)
                }
                Button("Choose folder…") { appState.pickVaultFolder() }
                Button(AppMenuCopy.revealVaultInFinder) { settings.revealVaultInFinder() }
            }

            Section("Index exclusion") {
                Toggle(
                    "Show Exclude from Index confirmation",
                    isOn: Binding(
                        get: { !settings.suppressExcludeFromIndexConfirmation },
                        set: { show in
                            if show {
                                settings.resetExcludeFromIndexConfirmation()
                            } else {
                                settings.suppressExcludeFromIndexConfirmation = true
                            }
                        }
                    )
                )
                Text("When off, Exclude from Index… runs immediately. You can turn confirmations back on here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Vault organization") {
                Toggle(VaultOrganizationHelp.toggleTitle, isOn: $settings.organizesVaultFiles)
                Text(settings.vaultOrganizationExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Learn more about file management…") {
                    VaultOrganizationHelp.presentHelpAlert()
                }
                .font(.caption)
            }

            Section("Export defaults") {
                Picker("Default layout", selection: $settings.exportLayoutMode) {
                    ForEach(ExportLayoutMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Text(settings.exportLayoutMode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Used for drag-out export and as the starting choice in File → Export Fonts…. Changing layout in the export panel applies only to that export.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Import defaults") {
                Text("Default formats and copy/move for drag-and-drop import and as the starting choices in File → Import Fonts…. Changing options in the import panel applies only to that import.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("OpenType (.otf, .otc)", isOn: formatBinding(\.openType))
                    .disabled(!settings.organizesVaultFiles)
                Toggle("TrueType (.ttf, .ttc, .dfont)", isOn: formatBinding(\.trueType))
                    .disabled(!settings.organizesVaultFiles)
                Toggle("Web fonts (.woff, .woff2)", isOn: formatBinding(\.webFonts))
                    .disabled(!settings.organizesVaultFiles)
                Picker("Into vault", selection: $settings.importOperation) {
                    Text(ImportFileOperation.copy.label).tag(ImportFileOperation.copy)
                    Text(ImportFileOperation.move.label).tag(ImportFileOperation.move)
                }
                .disabled(!settings.organizesVaultFiles)
            }

            Section("Distribution") {
                Text("This build runs without App Sandbox (development). Mac App Store builds will enable sandboxing later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Font table

struct FontTableSettingsTab: View {
    @ObservedObject private var settings = VaultSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Turn columns on or off and drag to reorder. The Name column stays first in the font table.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("In the font table: click a header to sort; drag a header to reorder; drag a divider to resize; right-click a header for visibility.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Picker("Row layout", selection: $settings.listRowDensity) {
                    ForEach(FontListRowDensity.allCases) { density in
                        Text(density.label).tag(density)
                    }
                }
                .pickerStyle(.segmented)
                Text(settings.listRowDensity.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            List {
                ForEach(settings.listColumnOrder) { column in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(column == .name ? .quaternary : .secondary)
                            .frame(width: 16)
                        Toggle(isOn: columnBinding(column)) {
                            Text(column.title)
                        }
                        .disabled(column.isRequired)
                    }
                }
                .onMove { settings.moveListColumn(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.inset)

            HStack {
                Button(AppMenuCopy.resetColumnWidths) { settings.resetListColumnWidths() }
                Button("Reset to Defaults") { settings.resetListColumnsToDefault() }
                Spacer()
            }
        }
        .padding(20)
    }

    private func columnBinding(_ column: FontListColumn) -> Binding<Bool> {
        Binding(
            get: { settings.isListColumnVisible(column) },
            set: { settings.setListColumnVisible(column, visible: $0) }
        )
    }
}

// MARK: - Inspector

struct InspectorSettingsTab: View {
    @ObservedObject private var settings = VaultSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose which fields appear in the Information panel. Values come from the catalog (rebuild if metadata looks stale).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach(InspectorFieldSection.allCases, id: \.rawValue) { section in
                    Section(section.rawValue) {
                        ForEach(InspectorField.allCases.filter { $0.section == section }) { field in
                            Toggle(isOn: fieldBinding(field)) {
                                Text(field.label)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)

            HStack {
                Button("Reset to Defaults") { settings.resetInspectorFieldsToDefault() }
                Spacer()
            }
        }
        .padding(20)
    }

    private func fieldBinding(_ field: InspectorField) -> Binding<Bool> {
        Binding(
            get: { settings.visibleInspectorFields.contains(field) },
            set: { settings.setInspectorFieldVisible(field, visible: $0) }
        )
    }
}

// MARK: - Vault maintenance

private struct VaultSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = VaultSettings.shared

    var body: some View {
        Form {
            Section("Catalog") {
                Text("Same commands as the Vault menu. Scan/Rebuild is also on the toolbar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(settings.catalogScanMenuTitle) { appState.indexVault() }
                if settings.organizesVaultFiles {
                    Button(AppMenuCopy.reorganizeLayout) { appState.reorganizeVault() }
                }
                Button(AppMenuCopy.cleanVault) { appState.presentCleanVault() }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
