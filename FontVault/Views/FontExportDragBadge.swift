import AppKit

/// FEX-style drag image: document icon with a count badge.
enum FontExportDragBadge {
    static let dragImageSize = NSSize(width: 52, height: 52)

    static func image(count: Int) -> NSImage {
        let image = NSImage(size: dragImageSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        if let doc = NSImage(systemSymbolName: "doc.fill", accessibilityDescription: nil) {
            doc.isTemplate = false
            doc.draw(in: NSRect(x: 6, y: 14, width: 30, height: 34))
        }

        if count > 1 {
            drawBadge(count: count)
        }

        return image
    }

    private static func drawBadge(count: Int) {
        let badgeRect = NSRect(x: 26, y: 2, width: 24, height: 24)
        NSColor(calibratedRed: 0.85, green: 0.15, blue: 0.12, alpha: 1).setFill()
        NSBezierPath(ovalIn: badgeRect).fill()

        let text = "\(count)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        let size = text.size(withAttributes: attrs)
        let origin = NSPoint(
            x: badgeRect.midX - size.width / 2,
            y: badgeRect.midY - size.height / 2
        )
        text.draw(at: origin, withAttributes: attrs)
    }
}
