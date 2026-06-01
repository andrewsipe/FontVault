import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Inspector window (double-click a font row)

/// Full metadata window (separate, movable, resizable — FEX-style).
struct FontInspectorWindowView: View {
    @ObservedObject var model: FontInspectorWindowModel
    @State private var draggedTabVaultPath: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            FontInspectorTabBar(model: model, draggedVaultPath: $draggedTabVaultPath)
            Divider()
            FontInspectorDetailBody(font: model.font, showAllCatalogFields: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(
                    of: [UTType.plainText],
                    delegate: FontInspectorTabDragCancelDropDelegate(onCancel: {
                        draggedTabVaultPath = nil
                    })
                )
        }
        .frame(
            minWidth: DesignMetrics.fontInspectorWindowMinWidth,
            maxWidth: .infinity,
            minHeight: DesignMetrics.fontInspectorWindowMinHeight,
            maxHeight: .infinity
        )
        .coordinateSpace(name: FontInspectorCoordinateSpace.inspectorWindow)
        .background { inspectorKeyboardShortcuts }
    }

    @ViewBuilder
    private var inspectorKeyboardShortcuts: some View {
        Group {
            Button("") { model.stepTab(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(!model.canStepTabBack)
            Button("") { model.stepTab(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(!model.canStepTabForward)
            Button("") { model.onCloseWindow?() }
                .keyboardShortcut("w", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.font.preferredFullName)
                .font(.headline)
                .lineLimit(2)
            Text(model.font.vaultPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

// MARK: - Tabs + navigation

private enum FontInspectorTabChrome {
    /// Full system accent (Highlight color) for the active tab.
    static var selectedBackground: Color {
        Color(nsColor: .controlAccentColor)
    }

    /// Label on the accent pill (typically white).
    static var selectedForeground: Color {
        Color(nsColor: .alternateSelectedControlTextColor)
    }

    /// Dim accent wash for non-selected tabs on hover.
    static var hoverBackground: Color {
        Color(nsColor: .controlAccentColor).opacity(0.14)
    }
}

private enum FontInspectorCoordinateSpace {
    static let tabStrip = "fontInspectorTabStrip"
    static let tabBarViewport = "fontInspectorTabBarViewport"
    static let inspectorWindow = "inspectorWindow"
}

private struct TabStripViewportFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// Clears in-progress tab reorder when the drag ends over a non-strip target.
private struct FontInspectorTabDragCancelDropDelegate: DropDelegate {
    let onCancel: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText])
    }

    func performDrop(info: DropInfo) -> Bool {
        onCancel()
        return false
    }
}

/// Drop target for the tab strip — uses `DropInfo.location` for insertion index (pick up and place).
private struct FontInspectorTabStripDropDelegate: DropDelegate {
    let model: FontInspectorWindowModel
    @Binding var draggedVaultPath: String?
    @Binding var insertionIndex: Int?
    let tabFrames: [String: CGRect]
    let scrollProxy: ScrollViewProxy
    let visibleMinX: CGFloat
    let visibleMaxX: CGFloat
    @Binding var lastEdgeScrollTime: Date

    func validateDrop(info: DropInfo) -> Bool {
        draggedVaultPath != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let stripX = info.location.x
        insertionIndex = destinationIndex(forX: stripX)
        autoScrollDuringDrag(stripX: stripX)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        insertionIndex = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { clearDragState() }

        guard let path = draggedVaultPath,
              let fromIndex = model.fonts.firstIndex(where: { $0.vaultPath == path }),
              let insert = insertionIndex else { return false }

        var toIndex = insert
        if toIndex > fromIndex { toIndex -= 1 }
        guard toIndex != fromIndex else { return true }

        withAnimation(.easeInOut(duration: 0.2)) {
            model.moveTab(from: fromIndex, to: toIndex)
        }
        return true
    }

    private func clearDragState() {
        draggedVaultPath = nil
        insertionIndex = nil
        lastEdgeScrollTime = .distantPast
    }

    private func destinationIndex(forX x: CGFloat) -> Int {
        for (index, font) in model.fonts.enumerated() {
            guard let frame = tabFrames[font.vaultPath] else { continue }
            if x < frame.midX { return index }
        }
        return model.fonts.count
    }

    private func autoScrollDuringDrag(stripX: CGFloat) {
        let edge = DesignMetrics.fontInspectorTabDragEdgeScrollThreshold
        let now = Date()
        guard now.timeIntervalSince(lastEdgeScrollTime) >= 0.1 else { return }

        if stripX < visibleMinX + edge {
            if scrollOneTabTowardStart() { lastEdgeScrollTime = now }
        } else if stripX > visibleMaxX - edge {
            if scrollOneTabTowardEnd() { lastEdgeScrollTime = now }
        }
    }

    @discardableResult
    private func scrollOneTabTowardStart() -> Bool {
        for index in model.fonts.indices {
            let font = model.fonts[index]
            guard let frame = tabFrames[font.vaultPath], frame.minX < visibleMinX - 2 else { continue }
            withAnimation(.linear(duration: 0.12)) {
                scrollProxy.scrollTo(font.vaultPath, anchor: .leading)
            }
            return true
        }
        return false
    }

    @discardableResult
    private func scrollOneTabTowardEnd() -> Bool {
        for index in model.fonts.indices.reversed() {
            let font = model.fonts[index]
            guard let frame = tabFrames[font.vaultPath], frame.maxX > visibleMaxX + 2 else { continue }
            withAnimation(.linear(duration: 0.12)) {
                scrollProxy.scrollTo(font.vaultPath, anchor: .trailing)
            }
            return true
        }
        return false
    }
}

private struct FontInspectorTabFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct FontInspectorTabBar: View {
    @ObservedObject var model: FontInspectorWindowModel
    @Binding var draggedVaultPath: String?

    @State private var insertionIndex: Int?
    @State private var tabFrames: [String: CGRect] = [:]
    @State private var tabStripFrameInViewport: CGRect = .zero
    @State private var tabBarViewportWidth: CGFloat = 0
    @State private var lastEdgeScrollTime: Date = .distantPast

    var body: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    tabStrip
                        .coordinateSpace(name: FontInspectorCoordinateSpace.tabStrip)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: TabStripViewportFrameKey.self,
                                    value: geometry.frame(
                                        in: .named(FontInspectorCoordinateSpace.tabBarViewport)
                                    )
                                )
                            }
                        )
                        .onPreferenceChange(FontInspectorTabFramePreferenceKey.self) { frames in
                            tabFrames = frames
                        }
                        .onDrop(
                            of: [UTType.plainText],
                            delegate: FontInspectorTabStripDropDelegate(
                                model: model,
                                draggedVaultPath: $draggedVaultPath,
                                insertionIndex: $insertionIndex,
                                tabFrames: tabFrames,
                                scrollProxy: proxy,
                                visibleMinX: visibleMinX,
                                visibleMaxX: visibleMaxX,
                                lastEdgeScrollTime: $lastEdgeScrollTime
                            )
                        )
                }
                .coordinateSpace(name: FontInspectorCoordinateSpace.tabBarViewport)
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear { tabBarViewportWidth = geometry.size.width }
                            .onChange(of: geometry.size.width) { _, width in
                                tabBarViewportWidth = width
                            }
                    }
                )
                .onPreferenceChange(TabStripViewportFrameKey.self) { frame in
                    tabStripFrameInViewport = frame
                }
                .onAppear {
                    scrollToSelectedTab(proxy: proxy, index: model.selectedIndex)
                }
                .onChange(of: model.selectedIndex) { _, newIndex in
                    scrollToSelectedTab(proxy: proxy, index: newIndex)
                }
            }

            HStack(spacing: 6) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.6))
                    .frame(width: 0.5, height: DesignMetrics.fontInspectorTabSeparatorHeight)
                FontInspectorStepButtons(model: model)
            }
            .frame(height: DesignMetrics.fontInspectorTabBarHeight)
        }
        .frame(height: DesignMetrics.fontInspectorTabBarHeight)
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(
            of: [UTType.plainText],
            delegate: FontInspectorTabDragCancelDropDelegate(onCancel: clearDragState)
        )
    }

    private func clearDragState() {
        draggedVaultPath = nil
        insertionIndex = nil
        lastEdgeScrollTime = .distantPast
    }

    private var visibleMinX: CGFloat {
        -tabStripFrameInViewport.minX
    }

    private var visibleMaxX: CGFloat {
        visibleMinX + tabBarViewportWidth
    }

    private var tabStrip: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(Array(model.fonts.enumerated()), id: \.element.vaultPath) { index, font in
                HStack(spacing: 0) {
                    if insertionIndex == index {
                        insertionLine
                    }
                    tabView(at: index, font: font)
                }
                if index < model.fonts.count - 1, draggedVaultPath == nil {
                    tabSeparator
                }
            }
            if insertionIndex == model.fonts.count {
                insertionLine
            }
        }
        .frame(height: DesignMetrics.fontInspectorTabBarHeight)
    }

    private var tabSeparator: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.5))
            .frame(width: 0.5, height: DesignMetrics.fontInspectorTabSeparatorHeight)
    }

    private var insertionLine: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(Color.accentColor)
            .frame(width: 2, height: DesignMetrics.fontInspectorTabPillHeight)
            .padding(.horizontal, 2)
            .transition(.opacity.animation(.easeInOut(duration: 0.1)))
    }

    @ViewBuilder
    private func tabView(at index: Int, font: FontRecord) -> some View {
        FontInspectorTab(
            title: font.preferredFullName,
            vaultPath: font.vaultPath,
            isSelected: index == model.selectedIndex,
            tabStripCoordinateSpace: FontInspectorCoordinateSpace.tabStrip,
            onSelect: { model.selectTab(at: index) },
            onClose: { model.closeTab(at: index) },
            onOpenInNewWindow: { model.openInNewWindow(tabAt: index) },
            onDragStarted: { draggedVaultPath = font.vaultPath }
        )
        .id(font.vaultPath)
        .opacity(draggedVaultPath == font.vaultPath ? 0.35 : 1)
        .contextMenu {
            Button("Open in New Window") {
                model.openInNewWindow(tabAt: index)
            }
            Button("Move to New Window") {
                model.detachTab(at: index)
            }
            Divider()
            Button("Close Tab", role: .destructive) {
                model.closeTab(at: index)
            }
        }
    }

    private func scrollToSelectedTab(proxy: ScrollViewProxy, index: Int) {
        guard model.fonts.indices.contains(index) else { return }
        let path = model.fonts[index].vaultPath
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(path, anchor: .center)
            }
        }
    }

}

/// Visual chrome for a tab pill (used by the system drag preview).
private struct FontInspectorTabPill: View {
    let title: String
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(FontInspectorTabChrome.selectedForeground)
                .lineLimit(1)
                .truncationMode(.middle)
            Color.clear
                .frame(
                    width: DesignMetrics.fontInspectorTabCloseButtonSize,
                    height: DesignMetrics.fontInspectorTabCloseButtonSize
                )
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: DesignMetrics.fontInspectorTabMaxWidth, alignment: .leading)
        .frame(height: DesignMetrics.fontInspectorTabPillHeight)
        .background {
            RoundedRectangle(cornerRadius: DesignMetrics.fontInspectorTabCornerRadius, style: .continuous)
                .fill(FontInspectorTabChrome.selectedBackground)
        }
    }
}

struct FontInspectorStepButtons: View {
    @ObservedObject var model: FontInspectorWindowModel

    var body: some View {
        HStack(spacing: 4) {
            stepButton(
                systemName: "arrowtriangle.backward",
                enabled: model.canStepTabBack,
                action: { model.stepTab(by: -1) }
            )
            stepButton(
                systemName: "arrowtriangle.forward",
                enabled: model.canStepTabForward,
                action: { model.stepTab(by: 1) }
            )
        }
    }

    private func stepButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(enabled ? .primary : .tertiary)
                .frame(
                    width: DesignMetrics.fontInspectorNavButtonWidth,
                    height: DesignMetrics.fontInspectorNavButtonWidth
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct FontInspectorTab: View {
    let title: String
    let vaultPath: String
    let isSelected: Bool
    let tabStripCoordinateSpace: String
    let onSelect: () -> Void
    let onClose: () -> Void
    let onOpenInNewWindow: () -> Void
    let onDragStarted: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            tabTitle
            closeButton
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: DesignMetrics.fontInspectorTabMaxWidth, alignment: .leading)
        .frame(height: DesignMetrics.fontInspectorTabPillHeight)
        .background {
            RoundedRectangle(cornerRadius: DesignMetrics.fontInspectorTabCornerRadius, style: .continuous)
                .fill(tabBackground)
        }
        .contentShape(RoundedRectangle(cornerRadius: DesignMetrics.fontInspectorTabCornerRadius, style: .continuous))
        .simultaneousGesture(tabTapGesture)
        .onDrag {
            onDragStarted()
            return NSItemProvider(object: vaultPath as NSString)
        } preview: {
            FontInspectorTabPill(title: title, isSelected: isSelected)
                .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
        }
        .background(tabFrameReader)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(
            String(localized: "Selects this font. Double-click to open in a new window. Drag to reorder.")
        )
        .help("Drag to reorder · double-click to open in a new window")
    }

    private var tabFrameReader: some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: FontInspectorTabFramePreferenceKey.self,
                value: [vaultPath: geometry.frame(in: .named(tabStripCoordinateSpace))]
            )
        }
    }

    private var tabTitle: some View {
        Text(title)
            .font(isSelected ? .caption.weight(.semibold) : .caption)
            .foregroundStyle(
                isSelected ? FontInspectorTabChrome.selectedForeground : Color.secondary
            )
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var tabTapGesture: some Gesture {
        let doubleTap = TapGesture(count: 2).onEnded { onOpenInNewWindow() }
        let singleTap = TapGesture(count: 1).onEnded { onSelect() }
        return doubleTap.exclusively(before: singleTap)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            ZStack {
                Circle()
                    .fill(closeButtonCircleFill)
                Image(systemName: "xmark")
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundStyle(closeButtonForeground)
            }
        }
        .buttonStyle(.plain)
        .frame(
            width: DesignMetrics.fontInspectorTabCloseButtonSize,
            height: DesignMetrics.fontInspectorTabCloseButtonSize
        )
        .contentShape(Circle())
        .opacity(isSelected || isHovering ? 1 : 0)
        .allowsHitTesting(isSelected || isHovering)
        .accessibilityHidden(!(isSelected || isHovering))
        .accessibilityLabel(String(localized: "Close tab"))
        .accessibilityHint(String(localized: "Closes \(title)"))
        .help("Close tab")
    }

    private var tabBackground: Color {
        if isSelected { return FontInspectorTabChrome.selectedBackground }
        if isHovering { return FontInspectorTabChrome.hoverBackground }
        return Color.clear
    }

    private var closeButtonForeground: Color {
        if isSelected {
            return FontInspectorTabChrome.selectedForeground.opacity(0.9)
        }
        return Color(nsColor: .secondaryLabelColor)
    }

    private var closeButtonCircleFill: Color {
        if isSelected {
            return FontInspectorTabChrome.selectedForeground.opacity(isHovering ? 0.22 : 0.12)
        }
        return Color(nsColor: .tertiaryLabelColor).opacity(isHovering ? 0.25 : 0)
    }
}

// MARK: - Shared detail list (sidebar + modal)

/// Scrollable key/value sections for one font record.
struct FontInspectorDetailBody: View {
    let font: FontRecord
    /// When true, every catalog field is listed (modal). When false, respects Settings → Information.
    var showAllCatalogFields: Bool
    var showsHeader: Bool = false

    @ObservedObject private var settings = VaultSettings.shared

    private var catalogFields: [InspectorField] {
        if showAllCatalogFields {
            return InspectorField.allCases
        }
        return settings.visibleInspectorFields
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if showsHeader {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(font.preferredFullName)
                                .font(.headline)
                            if font.isVariable {
                                FontInspectorVariableDot()
                            }
                        }
                        Text(
                            "\(font.preferredFamily) · \(font.format.uppercased()) · \(ByteCountFormatter.string(fromByteCount: font.fileSize, countStyle: .file))"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                FontInspectorSection(title: "Catalog") {
                    FontInspectorRow(key: "Full name", value: font.preferredFullName)
                    FontInspectorRowDivider()
                    FontInspectorRow(key: "Full Name (ID 4)", value: font.nameTableFullName)
                    FontInspectorRowDivider()
                    FontInspectorRow(key: "Foundry", value: font.foundry)
                    FontInspectorRowDivider()
                    FontInspectorRow(
                        key: "Variable font",
                        value: font.isVariable ? variableFontSummary : "No"
                    )
                    FontInspectorRowDivider()
                    FontInspectorRow(
                        key: "Excluded from index",
                        value: font.excludedFromIndex ? "Yes" : "No"
                    )
                }

                if font.isVariable {
                    FontInspectorSection(title: "Variable font") {
                        FontInspectorRow(
                            key: "Variable font",
                            value: variableFontSummary
                        )
                    }
                }

                if settings.showMetadataWarnings, font.hasAnyActiveMetadataIssue {
                    FontInspectorSection(title: "Metadata issues") {
                        let issueRows = metadataIssueRows(for: font)
                        ForEach(Array(issueRows.enumerated()), id: \.element.field) { index, row in
                            if index > 0 { FontInspectorRowDivider() }
                            FontInspectorRow(
                                key: row.label,
                                value: row.value,
                                issues: row.issues
                            )
                        }
                    }
                }

                ForEach(InspectorFieldSection.allCases, id: \.rawValue) { section in
                    let fields = catalogFields.filter { $0.section == section }
                    if !fields.isEmpty {
                        FontInspectorSection(title: section.rawValue) {
                            ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                                if index > 0 { FontInspectorRowDivider() }
                                FontInspectorRow(
                                    key: field.label,
                                    value: field.value(from: font),
                                    mono: field.usesMonospace,
                                    issues: settings.showMetadataWarnings
                                        ? (field.metadataFieldKey.map {
                                            font.activeMetadataIssues(for: $0)
                                        } ?? [])
                                        : [],
                                    copyMenuTitle: field == .sha256 ? "Copy SHA-256" : nil
                                )
                            }
                        }
                    }
                }

                ForEach(Array(font.extractedDetails.inspectorSections().enumerated()), id: \.offset) { _, section in
                    FontInspectorSection(title: section.title) {
                        ForEach(Array(section.rows.enumerated()), id: \.offset) { index, row in
                            if index > 0 { FontInspectorRowDivider() }
                            FontInspectorRow(
                                key: row.label,
                                value: row.value,
                                numeric: FontInspectorRow.looksNumeric(row.value)
                            )
                        }
                    }
                }

                if font.extractedDetails.isEmpty {
                    FontInspectorSection(title: "Extracted details") {
                        FontInspectorRow(
                            key: "Status",
                            value: "No extended metadata (rebuild catalog after upgrading)"
                        )
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var variableFontSummary: String {
        if let count = font.extractedDetails.variableAxisCount, count > 0 {
            return "Yes (\(count) \(count == 1 ? "axis" : "axes"))"
        }
        return "Yes"
    }

    private struct MetadataIssueRow {
        let field: FontMetadataFieldKey
        let label: String
        let value: String
        let issues: [MetadataIssue]
    }

    private func metadataIssueRows(for font: FontRecord) -> [MetadataIssueRow] {
        FontMetadataFieldKey.allCases.compactMap { field in
            let issues = font.activeMetadataIssues(for: field)
            guard !issues.isEmpty else { return nil }
            let value: String
            switch field {
            case .psName: value = font.psName
            case .fullName: value = font.fullName
            case .family: value = font.family
            case .subfamily: value = font.subfamily
            case .typographicFamily: value = font.typographicFamily
            case .typographicSubfamily: value = font.typographicSubfamily
            case .version: value = font.version
            case .manufacturer: value = font.manufacturer
            case .vendorID: value = font.vendorID
            case .copyright: value = font.copyright
            case .uniqueName: value = font.uniqueName
            case .description: value = font.description
            case .designer: value = font.designer
            case .trademark: value = font.trademark
            case .formatDetailed: value = font.formatDetailed
            }
            let label = InspectorField.allCases.first { $0.metadataFieldKey == field }?.label
                ?? field.rawValue
            return MetadataIssueRow(field: field, label: label, value: value, issues: issues)
        }
    }
}

// MARK: - Rows & sections

struct FontInspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().opacity(0.35)
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            content
        }
    }
}

struct FontInspectorRowDivider: View {
    var body: some View {
        Divider().opacity(0.35)
    }
}

struct FontInspectorRow: View {
    let key: String
    let value: String
    var mono: Bool = false
    var numeric: Bool = false
    var issues: [MetadataIssue] = []
    var copyMenuTitle: String?

    private var usesTopAlignment: Bool {
        value.contains("\n") || value.count > 56
    }

    private var valueIsURL: Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    static func looksNumeric(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.allSatisfy { $0.isNumber || ".,-+:%/() ".contains($0) }
    }

    var body: some View {
        HStack(alignment: usesTopAlignment ? .top : .firstTextBaseline, spacing: 6) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 120, maxWidth: 180, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            if !issues.isEmpty {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(MetadataIssue.tooltip(for: issues))
            }
            valueView
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .contextMenu {
            if let copyMenuTitle, !value.isEmpty {
                Button(copyMenuTitle) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                }
            }
        }
    }

    @ViewBuilder
    private var valueView: some View {
        if valueIsEmpty {
            Text("—")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if valueIsURL, let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            Link(destination: url) {
                valueText
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .textSelection(.enabled)
        } else {
            valueText
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var valueIsEmpty: Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var valueText: some View {
        if mono {
            Text(value)
                .font(.system(.caption, design: .monospaced))
        } else if numeric {
            Text(value)
                .font(.caption)
                .monospacedDigit()
        } else {
            Text(value)
                .font(.caption)
        }
    }
}

struct FontInspectorVariableDot: View {
    var body: some View {
        Circle()
            .fill(Color(nsColor: .systemPurple))
            .frame(width: 6, height: 6)
            .accessibilityLabel("Variable font")
    }
}
