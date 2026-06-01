import SwiftUI

/// FEX-style import sheet: title, progress bar + action on one row, detail text below.
struct ImportProgressSheet: View {
    let operation: ModalProgressOperation
    let state: ImportProgressState
    var importReport: ImportReport?
    let onCancel: () -> Void
    let onDone: () -> Void
    let onViewDetails: () -> Void

    private var showsCancel: Bool {
        guard !state.isComplete else { return false }
        switch operation {
        case .cleanVault:
            return false
        case .importFonts, .rebuildCatalog, .reorganizeVault:
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.controlSpacing + 6) {
            Text(state.title)
                .font(.headline)

            HStack(alignment: .center, spacing: DesignMetrics.sheetInlineActionSpacing) {
                Group {
                    if state.isComplete || state.total > 0 {
                        ProgressView(value: state.isComplete ? 1 : state.fraction)
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                }
                .frame(maxWidth: .infinity)

                if state.isComplete {
                    if operation == .importFonts,
                       let importReport,
                       importReport.hasInspectableRows {
                        SheetActionButton.secondaryInline(
                            AppMenuCopy.viewImportDetails,
                            action: onViewDetails
                        )
                    }
                    SheetActionButton.primaryInline("Okay", action: onDone)
                        .keyboardShortcut(.defaultAction)
                } else if showsCancel {
                    SheetActionButton.secondaryInline("Cancel", role: .cancel, action: onCancel)
                        .help(cancelHelp)
                        .keyboardShortcut(.cancelAction)
                }
            }

            detailBelowProgressBar
        }
        .padding(DesignMetrics.windowMargin + 4)
        .frame(width: 460)
    }

    private var cancelHelp: String {
        switch operation {
        case .rebuildCatalog: return "Cancel catalog rebuild"
        case .reorganizeVault: return "Cancel reorganize"
        case .importFonts: return "Cancel import"
        case .cleanVault: return ""
        }
    }

    @ViewBuilder
    private var detailBelowProgressBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            if state.isComplete {
                if operation == .importFonts, let importReport {
                    ImportCompletionSummaryView(report: importReport)
                } else {
                    Text(state.currentFileName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(state.currentFileName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(state.currentFileName)
                    .animation(.easeInOut(duration: 0.12), value: state.currentFileName)

                if !state.countLabel.isEmpty {
                    Text(state.countLabel)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
