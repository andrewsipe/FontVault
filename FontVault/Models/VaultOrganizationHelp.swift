import AppKit

/// User-facing copy for who manages font files on disk (Settings, onboarding, Help).
enum VaultOrganizationHelp {
    static let toggleTitle = "Font Vault manages font files on disk"

    static let managedExplanation = """
    Font Vault places imported fonts in A–Z folders, can reorganize the vault for you, and updates the catalog when you import or rebuild.

    Turn this off if you prefer to manage font files yourself in Finder inside the vault folder.
    """

    static let userManagedExplanation = """
    You manage font files in the vault folder (add, move, and remove them in Finder). Font Vault scans the folder and updates the font table when you use Scan Vault for Changes.

    Turn this on to let Font Vault import into A–Z layout and use Reorganize.
    """

    static let helpAlertTitle = "Who manages font files?"

    static let helpAlertMessage = """
    Font Vault can either manage font files in your vault or leave file placement to you.

    When Font Vault manages (Settings → General, toggle on):
    • Import Fonts… copies fonts into A–Z folders
    • Reorganize can move files into letter buckets
    • Rebuild Catalog… refreshes the catalog after imports

    When you manage (toggle off):
    • Add Fonts to Vault… opens the vault in Finder — you arrange files there
    • Scan Vault for Changes… updates the font table from what is on disk
    • Reorganize is hidden until Font Vault manages files again

    Export and drag-out use the layout in Settings → Export defaults (group by family, vault A–Z, or flat). File → Export Fonts… can pick a different layout for that export only.

    Import defaults (formats, copy vs move) live in Settings → Import defaults. The import panel and drag-and-drop follow those rules; panel choices do not change Settings.

    Change organization mode anytime in Settings → General.
    """

    @MainActor
    static func presentHelpAlert() {
        let alert = NSAlert()
        alert.messageText = helpAlertTitle
        alert.informativeText = helpAlertMessage
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
