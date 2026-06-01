import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = VaultSettings.shared
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Vault") {
                sidebarRow(
                    title: "All fonts",
                    count: settings.showLibraryCounters ? appState.catalogFontCount : nil,
                    systemImage: "externaldrive",
                    tag: .allFonts
                )
            }

            Section("Conflicts") {
                sidebarRow(
                    title: "Duplicates",
                    count: settings.showLibraryCounters && appState.duplicateFileCount > 0
                        ? appState.duplicateFileCount
                        : nil,
                    systemImage: "doc.on.doc",
                    tag: .duplicates
                )
            }

            Section("Format") {
                if appState.variableFontCount > 0 {
                    HStack(spacing: DesignMetrics.controlSpacing) {
                        FontVaultVariableFilterBadge()
                        Spacer(minLength: 4)
                        if settings.showLibraryCounters {
                            libraryCounterText(appState.variableFontCount)
                        }
                    }
                    .tag(SidebarItem.format(filterKey: FontSidebarFilter.variableOnly))
                    .accessibilityLabel(
                        settings.showLibraryCounters
                            ? "Variable fonts, \(appState.variableFontCount) fonts"
                            : "Variable fonts"
                    )
                }

                ForEach(appState.sidebarFormats, id: \.filterKey) { entry in
                    HStack(spacing: DesignMetrics.controlSpacing) {
                        FontVaultFormatBadge(format: entry.format)
                        Spacer(minLength: 4)
                        if settings.showLibraryCounters {
                            libraryCounterText(entry.count)
                        }
                    }
                    .tag(SidebarItem.format(filterKey: entry.filterKey))
                    .accessibilityLabel(
                        settings.showLibraryCounters
                            ? "\(entry.format.badgeLabel), \(entry.count) fonts"
                            : entry.format.badgeLabel
                    )
                }
            }

            Section("Smart Filters") {
                if appState.showsExcludedFontsSmartFilterRow {
                    sidebarRow(
                        title: AppMenuCopy.smartFilterExcludedFonts,
                        count: settings.showLibraryCounters ? appState.excludedFontCount : nil,
                        systemImage: "nosign",
                        tag: .smartFilter(.excludedFonts)
                    )
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Library")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            vaultPathFooter
        }
        .onChange(of: appState.sidebarSelection) { _, newValue in
            if selection != newValue {
                selection = newValue
            }
        }
        .onAppear {
            selection = appState.sidebarSelection
        }
    }

    private func libraryCounterText(_ value: Int) -> some View {
        Text(value, format: .number.grouping(.automatic))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.72))
            .monospacedDigit()
    }

    private func sidebarRow(
        title: String,
        count: Int?,
        systemImage: String,
        tag: SidebarItem
    ) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if let count {
                libraryCounterText(count)
            }
        }
        .tag(tag)
        .accessibilityLabel(count.map { "\(title), \($0) fonts" } ?? title)
    }

    @ViewBuilder
    private var vaultPathFooter: some View {
        if let url = settings.vaultRootURL {
            VStack(alignment: .leading, spacing: DesignMetrics.controlSpacing) {
                Divider()
                Text("Vault path")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text(url.path)
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Button(AppMenuCopy.revealVaultInFinder) {
                    settings.revealVaultInFinder()
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignMetrics.controlSpacing + 2)
        }
    }
}
