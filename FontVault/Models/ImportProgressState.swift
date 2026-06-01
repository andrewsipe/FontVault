import Foundation

enum ImportProgressPhase: Equatable {
    case active
    case complete(title: String, message: String)
}

/// Live import progress for the FEX-style modal sheet (`importTitle` / `importSubInfo` / bar).
struct ImportProgressState: Equatable {
    var phase: ImportProgressPhase = .active
    var title: String
    /// Current file name shown above the progress bar (FEX `importSubInfo`).
    var currentFileName: String
    var completed: Int
    var total: Int

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(completed) / Double(total))
    }

    var countLabel: String {
        guard total > 0 else { return "" }
        return "\(completed) of \(total)"
    }

    var isComplete: Bool {
        if case .complete = phase { return true }
        return false
    }

    static func active(
        title: String,
        fileName: String,
        completed: Int,
        total: Int
    ) -> ImportProgressState {
        ImportProgressState(
            phase: .active,
            title: title,
            currentFileName: fileName,
            completed: completed,
            total: total
        )
    }

    static func complete(title: String, message: String, total: Int) -> ImportProgressState {
        ImportProgressState(
            phase: .complete(title: title, message: message),
            title: title,
            currentFileName: message,
            completed: total,
            total: total
        )
    }
}

enum ImportProgressReporter {
    /// Show the modal progress sheet at or above this many font files (after scan).
    static let panelThreshold = 5
}

enum CatalogProgressReporter {
    /// Always show the modal sheet for rebuild (scan + metadata can take a while on large vaults).
    static let alwaysShowPanel = true
}

enum ModalProgressOperation: Equatable {
    case importFonts
    case rebuildCatalog
    case cleanVault
    case reorganizeVault
}

/// Stable identity for the import sheet so SwiftUI does not flash an empty sheet while dismissing.
struct ImportProgressSession: Identifiable {
    let id = UUID()
    var operation: ModalProgressOperation = .importFonts
    var state: ImportProgressState
    /// Populated when an import completes; drives optional “View Details…” on the progress sheet.
    var importReport: ImportReport?
}

struct CatalogIndexResult: Sendable {
    var scanned: Int = 0
    var added: Int = 0
    var updated: Int = 0
}
