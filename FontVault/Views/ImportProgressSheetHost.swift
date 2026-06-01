import SwiftUI

/// Presents import progress via `sheet(item:)` so dismissal never shows an empty sheet chrome.
struct ImportProgressSheetHost: View {
    @EnvironmentObject private var appState: AppState
    let session: ImportProgressSession
    /// Shown from the progress sheet; a second `.sheet` on the main window does not present while import progress is up.
    @State private var detailReport: ImportReport?

    var body: some View {
        ImportProgressSheet(
            operation: session.operation,
            state: session.state,
            importReport: session.importReport,
            onCancel: {
                switch session.operation {
                case .importFonts:
                    appState.cancelImportInProgress()
                case .rebuildCatalog:
                    appState.cancelCatalogRebuildInProgress()
                case .cleanVault:
                    appState.dismissImportProgress()
                case .reorganizeVault:
                    appState.cancelReorganizeInProgress()
                }
            },
            onDone: { appState.dismissImportProgress() },
            onViewDetails: { detailReport = session.importReport }
        )
        .interactiveDismissDisabled(!session.state.isComplete)
        .sheet(item: $detailReport) { report in
            ImportReportSheet(report: report)
                .environmentObject(appState)
        }
    }
}
