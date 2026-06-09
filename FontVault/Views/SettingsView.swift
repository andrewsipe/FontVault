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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        VStack(alignment: .leading, spacing: 0) {
            sortAndDensityControlBar
            Divider()
            columnList
            Divider()
            columnListFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(DesignMetrics.windowMargin)
    }

    // MARK: - Control bar (fixed height, non-scrolling)

    private var sortAndDensityControlBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 20) {
                settingsControlGroup(label: "Grouped sort") {
                    sortPresetPicker(selection: $settings.groupedListSortPreset)
                }
                settingsControlGroup(label: "Flat sort") {
                    sortPresetPicker(selection: $settings.flatListSortPreset)
                }
                Spacer(minLength: 12)
                settingsControlGroup(label: "Row density") {
                    Picker("", selection: $settings.listRowDensity) {
                        ForEach(FontListRowDensity.allCases) { density in
                            Text(density.label).tag(density)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            Text(sortControlCaption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 12)
    }

    private func sortPresetPicker(selection: Binding<FontListSortPreset>) -> some View {
        Picker("", selection: selection) {
            ForEach(FontListSortPreset.allCases) { preset in
                Text(preset.label).tag(preset)
            }
        }
        .labelsHidden()
        .frame(minWidth: 132)
    }

    private var sortControlCaption: String {
        let usesStyleOrder = settings.groupedListSortPreset == .styleOrder
            || settings.flatListSortPreset == .styleOrder
        if usesStyleOrder {
            return """
            Style order: width → weight → upright before italic → name. \
            A column-header sort overrides these until View → Reset List Sort to Default.
            """
        }
        return "A column-header sort overrides default sort until View → Reset List Sort to Default."
    }

    private func settingsControlGroup<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: - Column list (owns remaining vertical space)

    private var columnList: some View {
        List {
            Section {
                ForEach(settings.listColumnOrder) { column in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(column == .name ? .quaternary : .secondary)
                            .frame(width: 16)
                        HStack(spacing: 6) {
                            Text(column.title)
                                .foregroundStyle(column.isRequired ? .secondary : .primary)
                            if column.isRequired {
                                Text("required")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        Spacer(minLength: 0)
                        Toggle("", isOn: columnBinding(column))
                            .labelsHidden()
                            .disabled(column.isRequired)
                    }
                }
                .onMove { settings.moveListColumn(fromOffsets: $0, toOffset: $1) }
            } header: {
                visibleColumnsSectionHeader
            }
        }
        .listStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var visibleColumnsSectionHeader: some View {
        HStack(spacing: 10) {
            Text("Visible columns")
                .font(.caption)
                .fontWeight(.medium)
            Divider()
            Text("Drag to reorder · right-click headers in table for quick access")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .textCase(nil)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private var columnListFooter: some View {
        HStack(spacing: 8) {
            Button(AppMenuCopy.resetColumnWidths) { settings.resetListColumnWidths() }
            Button("Reset to Defaults") { settings.resetListColumnsToDefault() }
            Spacer()
        }
        .padding(.top, 10)
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
