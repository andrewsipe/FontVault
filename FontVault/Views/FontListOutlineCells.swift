import AppKit

// MARK: - Row metrics

enum FontListRowMetrics {
    static let singleLine: CGFloat = 28
    static let familyHeader: CGFloat = 30
    static let twoLineName: CGFloat = 46
    static let comfortableFamilyHeader: CGFloat = 38
    static let horizontalInset: CGFloat = 4

    static func rowHeight(density: FontListRowDensity, isFamily: Bool) -> CGFloat {
        switch density {
        case .compact:
            return isFamily ? familyHeader : singleLine
        case .comfortable:
            return isFamily ? comfortableFamilyHeader : twoLineName
        }
    }
}

/// Outline chrome shared by row hit-testing and the Name column header.
enum FontListOutlineChrome {
    /// Measured list body text in dark mode (RGB 220); `labelColor` in light mode.
    static func listBodyTextColor(for appearance: NSAppearance) -> NSColor {
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return NSColor(srgbRed: 220 / 255, green: 220 / 255, blue: 220 / 255, alpha: 1)
        default:
            return NSColor.labelColor
        }
    }

    /// For `NSTextField.textColor` (updates with appearance).
    static let listBodyTextNSColor = NSColor(name: "FontVaultListBodyText") { appearance in
        listBodyTextColor(for: appearance)
    }

    static let disclosureButtonIdentifier = NSUserInterfaceItemIdentifier("DisclosureButton")

    /// Replace system disclosure art (ignores `contentTintColor`) with palette-colored SF Symbols.
    static func styleDisclosureButton(_ button: NSButton, appearance: NSAppearance) {
        let tint = listBodyTextColor(for: appearance)
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))

        func chevron(_ symbolName: String) -> NSImage? {
            NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(symbolConfig)
        }

        button.isBordered = false
        button.bezelStyle = .inline
        button.imagePosition = .imageOnly
        button.image = chevron("chevron.right")
        button.alternateImage = chevron("chevron.down")
    }

    /// Re-apply disclosure styling when row views are created or reused.
    static func applyDisclosureTint(
        to rowView: NSTableRowView,
        level: Int,
        indentationPerLevel: CGFloat,
        appearance: NSAppearance
    ) {
        let maxX = disclosureHitMaxX(indentationPerLevel: indentationPerLevel, level: level) + 4
        styleDisclosureButtons(in: rowView, rowView: rowView, maxX: maxX, appearance: appearance)
    }

    private static func styleDisclosureButtons(
        in view: NSView,
        rowView: NSView,
        maxX: CGFloat,
        appearance: NSAppearance
    ) {
        if let button = view as? NSButton {
            let frameInRow = rowView.convert(view.bounds, from: view)
            if button.bezelStyle == .disclosure || frameInRow.maxX <= maxX {
                styleDisclosureButton(button, appearance: appearance)
            }
        }
        for subview in view.subviews {
            styleDisclosureButtons(in: subview, rowView: rowView, maxX: maxX, appearance: appearance)
        }
    }

    static let disclosureLeadPadding: CGFloat = 6

    /// Trailing edge of the expand/collapse hit zone (level 0 family row).
    static func disclosureHitMaxX(indentationPerLevel: CGFloat, level: Int) -> CGFloat {
        disclosureLeadPadding + indentationPerLevel * CGFloat(level + 1)
    }

    /// Leading inset for family row text and the Name header when grouped.
    static func nameColumnTextLeadingInset(indentationPerLevel: CGFloat) -> CGFloat {
        disclosureHitMaxX(indentationPerLevel: indentationPerLevel, level: 0)
    }

    static func nameColumnHeaderLeadingInset(
        indentationPerLevel: CGFloat,
        groupByFamily: Bool
    ) -> CGFloat {
        groupByFamily
            ? nameColumnTextLeadingInset(indentationPerLevel: indentationPerLevel)
            : FontListRowMetrics.horizontalInset
    }
}

// MARK: - Excluded-from-index appearance

enum FontListExcludedAppearance {
    static let contentAlpha: CGFloat = 0.62
    static let symbolName = "nosign"

    static func shouldDim(item: FontListOutlineItem, showIgnoredFonts: Bool) -> Bool {
        guard showIgnoredFonts else { return false }
        switch item {
        case .font(let font):
            return font.excludedFromIndex
        case .fontPath:
            return false
        case .family(let section):
            return section.allStylesExcludedFromIndex
        }
    }

    static func applyContentDimming(to view: NSView, dimmed: Bool) {
        view.alphaValue = dimmed ? contentAlpha : 1
    }
}

// MARK: - Row view (disclosure tint)

/// Row container that re-tints AppKit disclosure buttons when they are added.
final class FontListOutlineRowView: NSTableRowView {
    weak var hostingOutlineView: NSOutlineView?

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        retintDisclosureControls()
    }

    override func layout() {
        super.layout()
        retintDisclosureControls()
    }

    private func retintDisclosureControls() {
        guard let hostingOutlineView else { return }
        let row = hostingOutlineView.row(for: self)
        guard row >= 0 else { return }
        FontListOutlineChrome.applyDisclosureTint(
            to: self,
            level: hostingOutlineView.level(forRow: row),
            indentationPerLevel: hostingOutlineView.indentationPerLevel,
            appearance: hostingOutlineView.effectiveAppearance
        )
    }
}

// MARK: - Layout helpers

private enum FontOutlineCellLayout {
    static func lineHeight(for font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    static func centeredFrame(
        in bounds: NSRect,
        lineHeight: CGFloat,
        horizontalInset: CGFloat = FontListRowMetrics.horizontalInset
    ) -> NSRect {
        let width = max(0, bounds.width - horizontalInset * 2)
        let y = bounds.midY - lineHeight / 2
        return NSRect(x: horizontalInset, y: y, width: width, height: lineHeight)
    }
}

// MARK: - Variable font indicator (purple dot after name)

final class FontVariableIndicatorDotView: NSView {
    static let diameter: CGFloat = 6
    static let gapAfterText: CGFloat = 5

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.diameter, height: Self.diameter)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "Variable font"
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        toolTip = "Variable font"
        wantsLayer = true
    }

    override func layout() {
        super.layout()
        layer?.backgroundColor = NSColor.systemPurple.cgColor
        layer?.cornerRadius = Self.diameter / 2
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(NSSize(width: Self.diameter, height: Self.diameter))
    }
}

// MARK: - Name cell (SwiftUI FontVaultNameCell parity)

/// Primary + optional family subtitle with tooltip.
/// Does not set `NSTableCellView.textField` — AppKit’s built-in cell layout fights custom constraints on reuse.
final class FontOutlineNameCellView: NSTableCellView {
    private let primaryField = NSTextField(labelWithString: "")
    private let secondaryField = NSTextField(labelWithString: "")
    private let excludedBadge = NSImageView()
    private let variableDot = FontVariableIndicatorDotView(frame: .zero)
    private var showsStackedSubtitle = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        for field in [primaryField, secondaryField] {
            field.lineBreakMode = .byTruncatingTail
            field.cell?.truncatesLastVisibleLine = true
            field.cell?.lineBreakMode = .byTruncatingTail
            field.drawsBackground = false
            field.isBezeled = false
            field.isEditable = false
            addSubview(field)
        }
        secondaryField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        secondaryField.textColor = .secondaryLabelColor
        primaryField.textColor = FontListOutlineChrome.listBodyTextNSColor

        excludedBadge.imageScaling = .scaleProportionallyDown
        excludedBadge.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        excludedBadge.image = NSImage(
            systemSymbolName: FontListExcludedAppearance.symbolName,
            accessibilityDescription: "Excluded from index"
        )
        excludedBadge.isHidden = true
        addSubview(excludedBadge)

        variableDot.isHidden = true
        addSubview(variableDot)
    }

    override func layout() {
        super.layout()
        let inset = FontListRowMetrics.horizontalInset
        var leading = inset

        if !excludedBadge.isHidden {
            let lineH: CGFloat = 14
            excludedBadge.frame = NSRect(
                x: leading,
                y: (bounds.height - lineH) / 2,
                width: 18,
                height: lineH
            )
            leading += 18 + 4
        }

        let dotReserve: CGFloat = variableDot.isHidden
            ? 0
            : FontVariableIndicatorDotView.diameter + FontVariableIndicatorDotView.gapAfterText
        let textLeading = leading
        let contentWidth = max(0, bounds.width - textLeading - inset - dotReserve)

        if showsStackedSubtitle {
            let primaryFont = primaryField.font ?? .systemFont(ofSize: NSFont.systemFontSize)
            let secondaryFont = secondaryField.font ?? .systemFont(ofSize: NSFont.smallSystemFontSize)
            let primaryH = FontOutlineCellLayout.lineHeight(for: primaryFont)
            let secondaryH = FontOutlineCellLayout.lineHeight(for: secondaryFont)
            let gap: CGFloat = 3
            let blockH = primaryH + gap + secondaryH
            var y = (bounds.height - blockH) / 2

            primaryField.frame = NSRect(x: textLeading, y: y, width: contentWidth, height: primaryH)
            layoutVariableDot(alignedToPrimaryLineMidY: y + primaryH / 2)
            y += primaryH + gap
            secondaryField.frame = NSRect(x: textLeading, y: y, width: contentWidth, height: secondaryH)
            return
        }

        let font = primaryField.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let lineH = FontOutlineCellLayout.lineHeight(for: font)
        var singleLine = FontOutlineCellLayout.centeredFrame(
            in: bounds,
            lineHeight: lineH,
            horizontalInset: textLeading
        )
        singleLine.size.width = contentWidth
        primaryField.frame = singleLine
        layoutVariableDot(alignedToPrimaryLineMidY: singleLine.midY)
    }

    private func layoutVariableDot(alignedToPrimaryLineMidY midY: CGFloat) {
        guard !variableDot.isHidden else { return }
        let inset = FontListRowMetrics.horizontalInset
        let d = FontVariableIndicatorDotView.diameter
        let x = bounds.width - inset - d
        variableDot.frame = NSRect(x: x, y: midY - d / 2, width: d, height: d)
    }

    func configure(
        primary: String,
        secondary: String?,
        familyHeader: Bool,
        dimmedExcluded: Bool = false,
        showVariableDot: Bool = false
    ) {
        if let secondary, !secondary.isEmpty, !familyHeader {
            showsStackedSubtitle = true
            primaryField.font = .systemFont(ofSize: NSFont.systemFontSize)
            primaryField.stringValue = primary
            secondaryField.stringValue = secondary
            secondaryField.isHidden = false
            toolTip = "\(primary)\n\(secondary)"
        } else {
            showsStackedSubtitle = false
            primaryField.font = familyHeader
                ? .boldSystemFont(ofSize: NSFont.systemFontSize)
                : .systemFont(ofSize: NSFont.systemFontSize)
            primaryField.stringValue = primary
            secondaryField.isHidden = true
            toolTip = primary
        }
        excludedBadge.isHidden = !dimmedExcluded
        variableDot.isHidden = !showVariableDot || familyHeader
        FontListExcludedAppearance.applyContentDimming(to: primaryField, dimmed: dimmedExcluded)
        FontListExcludedAppearance.applyContentDimming(to: secondaryField, dimmed: dimmedExcluded)
        FontListExcludedAppearance.applyContentDimming(to: excludedBadge, dimmed: dimmedExcluded)
        FontListExcludedAppearance.applyContentDimming(to: variableDot, dimmed: dimmedExcluded)
        if dimmedExcluded {
            toolTip = (toolTip ?? primary) + "\nExcluded from index"
        }
        needsLayout = true
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        FontListExcludedAppearance.applyContentDimming(to: primaryField, dimmed: false)
        FontListExcludedAppearance.applyContentDimming(to: secondaryField, dimmed: false)
        FontListExcludedAppearance.applyContentDimming(to: excludedBadge, dimmed: false)
        excludedBadge.isHidden = true
        variableDot.isHidden = true
    }
}

// MARK: - Format badge (colored by format type)

final class FontOutlineFormatBadgeCellView: NSTableCellView {
    private let badgeBackground = NSView()
    private let label = NSTextField(labelWithString: "")
    private var activeFormat: FontFormat = .unknown
    private var mixFormatExtensions: [String] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        badgeBackground.wantsLayer = true
        badgeBackground.layer?.cornerRadius = 4

        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.alignment = .center
        label.lineBreakMode = .byClipping
        label.cell?.truncatesLastVisibleLine = false
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false

        badgeBackground.addSubview(label)
        addSubview(badgeBackground)
    }

    override func layout() {
        super.layout()
        let badgeHeight: CGFloat = 20
        let labelFont = label.font ?? .systemFont(ofSize: 11, weight: .semibold)
        let labelH = FontOutlineCellLayout.lineHeight(for: labelFont)
        let badgeWidth = activeFormat.preferredBadgeWidth

        badgeBackground.frame = NSRect(
            x: FontListRowMetrics.horizontalInset,
            y: (bounds.height - badgeHeight) / 2,
            width: badgeWidth,
            height: badgeHeight
        )
        label.frame = NSRect(
            x: 0,
            y: (badgeHeight - labelH) / 2,
            width: badgeWidth,
            height: labelH
        )
        FontFormatBadgeLayerStyle.layoutGradient(in: badgeBackground)
    }

    private static func measuredTextWidth(_ text: String, font: NSFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: font.boundingRectForFont.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        // Semibold glyphs can extend slightly past measured bounds.
        return ceil(rect.width) + 2
    }

    func configure(
        format: FontFormat,
        isVariable: Bool = false,
        mixFormatExtensions: [String] = [],
        dimmedExcluded: Bool = false
    ) {
        activeFormat = format
        self.mixFormatExtensions = mixFormatExtensions
        let display = format.badgeLabel
        label.stringValue = display
        FontFormatBadgeLayerStyle.apply(
            to: badgeBackground,
            format: format,
            isVariable: isVariable,
            mixFormatExtensions: mixFormatExtensions
        )
        label.textColor = format.badgeColors.foreground
        let tip: String?
        if format == .mixed {
            tip = FontFormat.mixedFormatsTooltip(fromExtensionStrings: mixFormatExtensions)
        } else if display == "?" {
            tip = nil
        } else if isVariable, format.supportsVariableGradient {
            tip = [display, "Variable font"].joined(separator: " · ")
        } else {
            tip = display
        }
        toolTip = tip
        FontListExcludedAppearance.applyContentDimming(to: self, dimmed: dimmedExcluded)
        needsLayout = true
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        FontFormatBadgeLayerStyle.apply(to: badgeBackground, format: .unknown, isVariable: false)
        mixFormatExtensions = []
        FontListExcludedAppearance.applyContentDimming(to: self, dimmed: false)
    }
}

// MARK: - Plain text cell

final class FontOutlineTextCellView: NSTableCellView {
    private let field = NSTextField(labelWithString: "")
    private(set) var openableLinkURL: URL?

    /// Opens the link when the cell was configured with `showsLink` (Cmd-click from the outline view).
    func openLinkIfPresent() -> Bool {
        guard let openableLinkURL else { return false }
        NSWorkspace.shared.open(openableLinkURL)
        return true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        field.lineBreakMode = .byTruncatingTail
        field.cell?.truncatesLastVisibleLine = true
        field.cell?.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.drawsBackground = false
        field.isBezeled = false
        field.isEditable = false
        addSubview(field)
    }

    override func layout() {
        super.layout()
        let horizontalInset = FontListRowMetrics.horizontalInset
        let font = field.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let lineH = FontOutlineCellLayout.lineHeight(for: font)
        let textBounds = bounds.insetBy(dx: horizontalInset, dy: 0)
        var fieldFrame = FontOutlineCellLayout.centeredFrame(in: textBounds, lineHeight: lineH)
        fieldFrame.size.width = max(0, textBounds.width)
        if field.alignment == .right {
            fieldFrame.origin.x = textBounds.maxX - fieldFrame.width
        } else {
            fieldFrame.origin.x = textBounds.minX
        }
        field.frame = fieldFrame
    }

    func configure(
        presentation: FontListCellPresentation,
        trailing: Bool,
        emphasized: Bool,
        showsTooltip: Bool,
        dimmedExcluded: Bool = false
    ) {
        configure(
            text: presentation.text,
            trailing: trailing,
            emphasized: emphasized,
            showsTooltip: showsTooltip,
            showsMetadataAttention: presentation.showsMetadataAttention,
            metadataAttentionDetail: presentation.metadataWarningDetail,
            showsLink: presentation.showsLink,
            linkURL: presentation.linkURL,
            dimmedExcluded: dimmedExcluded
        )
    }

    func configure(
        text: String,
        trailing: Bool,
        emphasized: Bool,
        showsTooltip: Bool,
        showsMetadataAttention: Bool = false,
        metadataAttentionDetail: String? = nil,
        showsLink: Bool = false,
        linkURL: URL? = nil,
        dimmedExcluded: Bool = false
    ) {
        let font: NSFont = emphasized
            ? .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            : .systemFont(ofSize: NSFont.systemFontSize)
        field.alignment = trailing ? .right : .left
        field.font = font

        openableLinkURL = showsLink && !showsMetadataAttention ? linkURL : nil

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: FontListOutlineChrome.listBodyTextNSColor,
        ]
        if showsMetadataAttention {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attributes[.underlineColor] = NSColor.systemOrange
        } else if openableLinkURL != nil {
            attributes[.foregroundColor] = NSColor.linkColor
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        field.attributedStringValue = NSAttributedString(string: text, attributes: attributes)

        if showsMetadataAttention, let metadataAttentionDetail, !metadataAttentionDetail.isEmpty {
            setAccessibilityLabel(metadataAttentionDetail)
        } else {
            setAccessibilityLabel(nil)
        }

        if showsTooltip, !text.isEmpty, text != ImportDateDisplay.conflictDisplay {
            field.toolTip = text
            toolTip = text
        } else {
            field.toolTip = nil
            toolTip = nil
        }

        FontListExcludedAppearance.applyContentDimming(to: self, dimmed: dimmedExcluded)
        needsLayout = true
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        openableLinkURL = nil
        field.attributedStringValue = NSAttributedString(string: "")
        setAccessibilityLabel(nil)
        field.toolTip = nil
        toolTip = nil
        FontListExcludedAppearance.applyContentDimming(to: self, dimmed: false)
    }
}
