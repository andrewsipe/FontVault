import Foundation

/// Narrow observation surface for selection-driven UI (inspector, status bar).
@MainActor
final class ListSelectionDisplay: ObservableObject {
    @Published private(set) var summary: String = ""
    @Published private(set) var primaryFont: FontRecord?
    @Published private(set) var selectedFonts: [FontRecord] = []
    @Published private(set) var selectionStatusDetail: ListStatusDetail?
    @Published private(set) var hoverStatusDetail: ListStatusDetail?

    /// Hover wins over selection when both are set (status bar uses this when idle).
    var activeStatusDetail: ListStatusDetail? {
        hoverStatusDetail ?? selectionStatusDetail
    }

    func update(summary: String, primaryFont: FontRecord?, selectedFonts: [FontRecord]) {
        self.summary = summary
        self.primaryFont = primaryFont
        self.selectedFonts = selectedFonts
    }

    func updateSelectionStatusDetail(_ detail: ListStatusDetail?) {
        selectionStatusDetail = detail
    }

    func updateHoverStatusDetail(_ detail: ListStatusDetail?) {
        hoverStatusDetail = detail
    }
}
