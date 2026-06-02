import SwiftUI

/// Per-file import outcomes (failed / skipped) after an import completes.
struct ImportReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    let report: ImportReport

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.controlSpacing) {
            Text(AppMenuCopy.importDetailsTitle)
                .font(.headline)

            ImportCompletionSummaryView(report: report)

            List {
                if !report.failed.isEmpty {
                    Section(AppMenuCopy.importReportFailedSection(report.failed.count)) {
                        ForEach(report.failed) { entry in
                            ImportReportEntryRow(entry: entry)
                        }
                    }
                }
                if !report.skippedEntries.isEmpty {
                    Section(AppMenuCopy.importReportSkippedSection(report.skippedEntries.count)) {
                        ForEach(report.skippedEntries) { entry in
                            ImportReportEntryRow(entry: entry)
                        }
                    }
                }
                if !report.namingFallbackEntries.isEmpty {
                    Section(AppMenuCopy.importReportNamingSection(report.namingFallbackEntries.count)) {
                        ForEach(report.namingFallbackEntries) { entry in
                            ImportReportEntryRow(entry: entry)
                        }
                    }
                }
            }
            .listStyle(.inset)

            HStack(spacing: DesignMetrics.sheetInlineActionSpacing) {
                Button(AppMenuCopy.copyImportIssueList) {
                    appState.copyImportIssueListToPasteboard(report)
                }
                .disabled(!report.hasExportableIssueRows)

                Button(AppMenuCopy.saveImportIssueList) {
                    appState.saveImportIssueList(report)
                }
                .disabled(!report.hasExportableIssueRows)

                Spacer()

                SheetActionButton.primary("Done") {
                    dismiss()
                    appState.dismissImportReport()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignMetrics.windowMargin + 4)
        .frame(width: 480)
        .frame(minHeight: 280, idealHeight: 380, maxHeight: 420)
    }
}

private struct ImportReportEntryRow: View {
    @EnvironmentObject private var appState: AppState
    let entry: ImportReportEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.displayName)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(entry.message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contextMenu {
            Button(AppMenuCopy.revealInFinder) {
                appState.revealImportEntryInFinder(entry)
            }
        }
    }
}
