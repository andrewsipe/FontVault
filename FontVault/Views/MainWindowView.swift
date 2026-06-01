import AppKit
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = VaultSettings.shared
    @FocusState private var isSearchFocused: Bool
    private var sidebarSelectionBinding: Binding<SidebarItem?> {
        Binding(
            get: { appState.sidebarSelection },
            set: { if let item = $0 { appState.selectSidebarItem(item) } }
        )
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { appState.prefersSidebarVisible ? .all : .detailOnly },
            set: { appState.prefersSidebarVisible = $0 != .detailOnly }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            SidebarView(selection: sidebarSelectionBinding)
                .navigationSplitViewColumnWidth(
                    min: DesignMetrics.sidebarMinWidth,
                    ideal: DesignMetrics.sidebarIdealWidth,
                    max: DesignMetrics.sidebarMaxWidth
                )
        } detail: {
            detailColumn
        }
        .fontVaultDropTarget()
        .sheet(item: $appState.importProgressSession) { session in
            ImportProgressSheetHost(session: session)
                .environmentObject(appState)
        }
        .sheet(item: $appState.importReportPresentation) { report in
            ImportReportSheet(report: report)
                .environmentObject(appState)
        }
        .onChange(of: appState.searchText, initial: false) { _, _ in appState.scheduleRefreshList() }
        .onChange(of: appState.formatFilter, initial: false) { _, _ in appState.scheduleRefreshList() }
        .onChange(of: appState.searchFocusRequest) { _, _ in
            focusSearchField()
        }
    }

    private func focusSearchField() {
        if #available(macOS 15.0, *) {
            isSearchFocused = true
        } else {
            FontVaultSearchFocus.focusInKeyWindow()
        }
    }

    private var detailColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Group {
                    switch appState.browserMode {
                    case .allFonts:
                        FontListView()
                    case .duplicates:
                        DuplicatesView()
                    }
                }
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)

                if appState.showInspector {
                    Divider()
                    InspectorView()
                        .frame(
                            minWidth: DesignMetrics.inspectorMinWidth,
                            idealWidth: DesignMetrics.inspectorIdealWidth,
                            maxWidth: DesignMetrics.inspectorMaxWidth
                        )
                }
            }

            StatusBarView()
        }
        .searchable(
            text: $appState.searchText,
            prompt: "Search name, family, foundry…"
        )
        .modifier(FontVaultSearchFocusModifier(isFocused: $isSearchFocused))
        .toolbar { mainToolbar }
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                appState.presentImportPanel()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .help("Import fonts into the vault")
            .disabled(appState.coordinator.isImporting)

            Button {
                appState.indexVault()
            } label: {
                Label(AppMenuCopy.rebuildCatalogToolbar, systemImage: "arrow.clockwise")
            }
            .help("Rebuild catalog from vault files (Vault → Rebuild Catalog…, ⇧⌘R)")
            .disabled(appState.coordinator.isIndexing || appState.coordinator.isImporting)
        }

        ToolbarItemGroup {
            Toggle(isOn: $appState.groupByFamily) {
                Label("Grouped", systemImage: "square.grid.2x2")
            }
            .help("Group list rows by font family")
            .disabled(appState.browserMode != .allFonts)
        }

        ToolbarItemGroup {
            Toggle(isOn: $appState.showInspector) {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help("Show or hide the inspector panel")
        }
    }
}

/// Applies `searchFocused` on macOS 15+; no-op on 14.x (focus uses AppKit walk).
private struct FontVaultSearchFocusModifier: ViewModifier {
    @FocusState.Binding var isFocused: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.searchFocused($isFocused)
        } else {
            content
        }
    }
}

private enum FontVaultSearchFocus {
    static func focusInKeyWindow() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        DispatchQueue.main.async {
            guard let field = findSearchField(in: window.contentView) else { return }
            window.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
    }

    private static func findSearchField(in view: NSView?) -> NSSearchField? {
        guard let view else { return nil }
        if let search = view as? NSSearchField { return search }
        for subview in view.subviews {
            if let found = findSearchField(in: subview) { return found }
        }
        return nil
    }
}

struct StatusBarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var selectionDisplay: ListSelectionDisplay
    @ObservedObject private var settings = VaultSettings.shared

    private var isShowingOperationProgress: Bool {
        appState.coordinator.isImporting
            || appState.coordinator.isIndexing
            || appState.coordinator.isExporting
            || appState.coordinator.isCleaning
    }

    private var visibleCount: StatusBarVisibleCount {
        appState.statusBarVisibleCount
    }

    private var showsSelectionZone: Bool {
        appState.statusBarSelectionGlance != nil && !selectionDisplay.summary.isEmpty
    }

    private var activeDetail: ListStatusDetail? {
        selectionDisplay.activeStatusDetail
    }

    var body: some View {
        HStack(spacing: 0) {
            visibleCountZone

            if showsSelectionZone {
                statusBarZoneDivider
                selectionCountZone
            }

            if !isShowingOperationProgress, let detail = activeDetail {
                statusBarZoneDivider
                cellDetailZone(detail)
                if settings.showMetadataWarnings, detail.rowHasMetadataIssue {
                    statusBarZoneDivider
                    warningZone(detail)
                }
            }

            Spacer(minLength: DesignMetrics.sectionSpacing)
            rightRail
        }
        .font(.caption)
        .padding(.horizontal, DesignMetrics.windowMargin)
        .frame(height: DesignMetrics.statusBarHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var statusBarZoneDivider: some View {
        Divider()
            .frame(height: 14)
            .padding(.horizontal, DesignMetrics.controlSpacing)
    }

    @ViewBuilder
    private var visibleCountZone: some View {
        HStack(spacing: 4) {
            statusBarIcon("tablecells")
            Text(visibleCount.glance)
            if let suffix = visibleCount.sourceSuffix {
                Text("·")
                    .foregroundStyle(.secondary)
                Text(suffix)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
        }
        .help(visibleCount.tooltip)
        .accessibilityLabel(visibleCount.tooltip)
    }

    @ViewBuilder
    private var selectionCountZone: some View {
        if let glance = appState.statusBarSelectionGlance {
            HStack(spacing: 4) {
                statusBarIcon("checkmark.circle")
                Text(glance)
            }
            .help(selectionDisplay.summary)
            .accessibilityLabel(selectionDisplay.summary)
        }
    }

    @ViewBuilder
    private func cellDetailZone(_ detail: ListStatusDetail) -> some View {
        HStack(spacing: 4) {
            if let column = detail.column {
                Text("\(column.title):")
                    .fontWeight(.semibold)
                Text(detail.valueText)
            } else {
                Text(detail.valueText)
            }
        }
        .lineLimit(1)
        .help(detail.tooltipLine)
        .accessibilityLabel(detail.tooltipLine)
    }

    @ViewBuilder
    private func warningZone(_ detail: ListStatusDetail) -> some View {
        let help = statusBarWarningHelp(for: detail)
        HStack(spacing: 4) {
            statusBarWarningIcon()
            if let issue = detail.metadataWarning {
                Text(issue.label)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
        .help(help)
        .accessibilityLabel(help)
    }

    private func statusBarWarningHelp(for detail: ListStatusDetail) -> String {
        if let issue = detail.metadataWarning {
            return issue.label
        }
        return detail.rowMetadataIssueTooltip
    }

    private func statusBarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.caption.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
    }

    private func statusBarWarningIcon() -> some View {
        Image(systemName: "exclamationmark.octagon.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
    }

    @ViewBuilder
    private var rightRail: some View {
        if appState.coordinator.isImporting {
            ProgressView()
                .controlSize(.small)
            Text(appState.coordinator.importProgress)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if appState.coordinator.isIndexing {
            ProgressView()
                .controlSize(.small)
            Text(appState.coordinator.indexProgress)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if appState.coordinator.isExporting {
            ProgressView()
                .controlSize(.small)
            Text(appState.coordinator.exportProgress)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if appState.coordinator.isCleaning {
            ProgressView()
                .controlSize(.small)
            Text(appState.coordinator.cleanProgress)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if appState.duplicateFileCount > 0, appState.browserMode == .allFonts {
            Button {
                appState.showDuplicates()
            } label: {
                Text("\(appState.duplicateFileCount) duplicate files — review")
            }
            .buttonStyle(.link)
            .font(.caption)
        } else if !isShowingOperationProgress,
                  selectionDisplay.activeStatusDetail == nil,
                  !appState.statusMessage.isEmpty {
            Text(appState.statusMessage)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
