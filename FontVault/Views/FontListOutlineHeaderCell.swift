import AppKit

/// Table header cell with left-aligned title and sort arrow on the trailing edge.
final class FontListOutlineHeaderCell: NSTableHeaderCell {
    enum SortIndicator {
        case none
        case ascending
        case descending
    }

    var sortIndicator: SortIndicator = .none
    /// Left padding for the title (Name column aligns with family row text past the chevron).
    var titleLeadingInset: CGFloat = 6

    override init(textCell string: String) {
        super.init(textCell: string)
        alignment = .left
        lineBreakMode = .byTruncatingTail
        truncatesLastVisibleLine = true
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        alignment = .left
        lineBreakMode = .byTruncatingTail
        truncatesLastVisibleLine = true
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: cellFrame).addClip()

        let trailingInset: CGFloat = 6
        let sortArrowReserve: CGFloat = 12
        let titleTrailingPad = trailingInset + (sortIndicator != .none ? sortArrowReserve + 4 : 0)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        paragraphStyle.alignment = .left

        let titleFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle,
        ]
        let title = stringValue as NSString
        let titleSize = title.size(withAttributes: titleAttributes)
        let titleY = cellFrame.midY - titleSize.height / 2
        let maxTitleWidth = max(0, cellFrame.width - titleLeadingInset - titleTrailingPad)
        let titleRect = NSRect(
            x: cellFrame.minX + titleLeadingInset,
            y: titleY,
            width: maxTitleWidth,
            height: titleSize.height
        )
        title.draw(
            with: titleRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: titleAttributes
        )

        if sortIndicator != .none {
            let arrow = sortIndicator == .ascending ? "\u{25B2}" : "\u{25BC}"
            let arrowFont = NSFont.systemFont(ofSize: 9, weight: .bold)
            let arrowColor = FontListOutlineChrome.listBodyTextColor(
                for: controlView.effectiveAppearance
            )
            let arrowAttributes: [NSAttributedString.Key: Any] = [
                .font: arrowFont,
                .foregroundColor: arrowColor,
            ]
            let arrowText = arrow as NSString
            let arrowSize = arrowText.size(withAttributes: arrowAttributes)
            let arrowX = cellFrame.maxX - trailingInset - arrowSize.width
            let arrowY = cellFrame.midY - arrowSize.height / 2
            arrowText.draw(
                in: NSRect(x: arrowX, y: arrowY, width: arrowSize.width, height: arrowSize.height),
                withAttributes: arrowAttributes
            )
        }

        NSGraphicsContext.restoreGraphicsState()
    }
}
