import AppKit

/// Marks drags that started inside Font Vault (export to Finder). Import drop must ignore these.
/// Internal-only type — not declared in Info.plist; detected via NSPasteboard, not UTType.
enum FontVaultDragTypes {
    static let exportDrag = NSPasteboard.PasteboardType("com.goodfont.fontvault.export-drag")

    static func markExportDrag(on pasteboard: NSPasteboard) {
        pasteboard.setString("1", forType: exportDrag)
    }

    static func isExportDrag(_ pasteboard: NSPasteboard?) -> Bool {
        pasteboard?.string(forType: exportDrag) != nil
    }

    static func isExportDragOnDragPasteboard() -> Bool {
        isExportDrag(NSPasteboard(name: .drag))
    }
}
