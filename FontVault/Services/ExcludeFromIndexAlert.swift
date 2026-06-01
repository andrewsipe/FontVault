import AppKit

/// Confirmation for **Exclude from Index…** (Phase 2).
enum ExcludeFromIndexAlert {
    private static let namePreviewLimit = 12

    @MainActor
    static func confirm(fonts: [FontRecord], suppressionAlreadyEnabled: Bool) -> (proceed: Bool, suppressFuture: Bool) {
        guard !fonts.isEmpty else { return (false, false) }
        if suppressionAlreadyEnabled {
            return (true, false)
        }

        let alert = NSAlert()
        let count = fonts.count
        alert.messageText = count == 1
            ? "Exclude “\(fonts[0].fullName)” from the index?"
            : "Exclude \(count) fonts from the index?"

        let names = fonts.prefix(namePreviewLimit).map(\.fullName).joined(separator: "\n")
        let more = count > namePreviewLimit ? "\n…and \(count - namePreviewLimit) more" : ""
        alert.informativeText = """
        \(names)\(more)

        Font files are not deleted or moved. While “Exclude Ignored Fonts from Index” is on, these fonts are skipped during vault scans. They stay visible in the font table until you turn off “Show Ignored Fonts” in the View menu.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Exclude from Index")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don’t show again"

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return (false, false) }
        let suppress = alert.suppressionButton?.state == .on
        return (true, suppress)
    }
}
