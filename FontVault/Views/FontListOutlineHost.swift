import AppKit
import SwiftUI

/// Column header with click-vs-drag differentiation for sort/reorder.
///
/// `NSTableHeaderView.mouseDown` runs an internal tracking loop that returns only on mouse up.
/// We capture state before/after to determine if it was a click (sort) or drag (reorder).
final class FontListOutlineHeaderView: NSTableHeaderView {
    weak var interaction: FontListOutlineCoordinator?

    private static let dragThreshold: CGFloat = 4

    override func rightMouseDown(with event: NSEvent) {
        showColumnMenu(for: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 {
            showColumnMenu(for: event)
        } else {
            super.otherMouseDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let startLocation = event.locationInWindow
        let localPoint = convert(startLocation, from: nil)

        // Find which column was clicked by checking header rects
        var clickedColumn: NSTableColumn?
        if let tableView = tableView {
            for (index, col) in tableView.tableColumns.enumerated() where !col.isHidden {
                let rect = headerRect(ofColumn: index)
                if rect.contains(localPoint) {
                    clickedColumn = col
                    break
                }
            }
        }

        // Capture column order before the tracking loop
        let columnOrderBefore = tableView?.tableColumns.map(\.identifier.rawValue) ?? []

        // Mark drag in progress to block applyStoredColumnOrderIfNeeded during drag
        interaction?.columnDragDidBegin()

        // This enters a tracking loop and returns on mouse up
        super.mouseDown(with: event)

        // Now we're at mouse up - check what happened
        guard let window = window else {
            interaction?.columnDragDidEnd()
            return
        }

        let currentMouseScreen = NSEvent.mouseLocation
        let currentMouseWindow = window.convertPoint(fromScreen: currentMouseScreen)
        let dx = currentMouseWindow.x - startLocation.x
        let dy = currentMouseWindow.y - startLocation.y
        let distanceSquared = dx * dx + dy * dy
        let wasDrag = distanceSquared >= Self.dragThreshold * Self.dragThreshold

        // Check if columns were reordered
        let columnOrderAfter = tableView?.tableColumns.map(\.identifier.rawValue) ?? []
        let columnsReordered = columnOrderBefore != columnOrderAfter

        // End the drag tracking
        interaction?.columnDragDidEnd()

        // If it was a simple click (not a drag, no reorder), trigger sort
        if !wasDrag, !columnsReordered, let clickedColumn = clickedColumn {
            interaction?.handleHeaderClick(for: clickedColumn, event: event)
        }
    }

    private func showColumnMenu(for event: NSEvent) {
        guard let menu = interaction?.columnHeaderContextMenu() else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

/// Outline view with Finder-style mouse handling (selection, export drag, context menu).
final class FontListOutlineView: NSOutlineView {
    weak var interaction: FontListOutlineCoordinator?

    override func makeView(withIdentifier identifier: NSUserInterfaceItemIdentifier, owner: Any?) -> NSView? {
        let view = super.makeView(withIdentifier: identifier, owner: owner)
        if identifier == FontListOutlineChrome.disclosureButtonIdentifier,
           let button = view as? NSButton {
            FontListOutlineChrome.styleDisclosureButton(button, appearance: effectiveAppearance)
        }
        return view
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        interaction?.retintVisibleDisclosureControls()
    }

    private enum PendingClick {
        case family(FontFamilySection)
        case font(String)
    }

    private var mouseDownLocation: NSPoint = .zero
    private var dragVaultPath: String?
    private var dragFamilySection: FontFamilySection?
    private var pendingClick: PendingClick?
    private var pendingMouseDownEvent: NSEvent?
    private var pendingSelectionWorkItem: DispatchWorkItem?
    private var didBeginExportDrag = false
    private var hoverTrackingArea: NSTrackingArea?
    static let exportDragThreshold: CGFloat = 6

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let options: NSTrackingArea.Options = [
            .mouseMoved,
            .mouseEnteredAndExited,
            .activeInKeyWindow,
            .inVisibleRect,
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        interaction?.updateHoverStatus(at: point, in: self)
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        interaction?.clearHoverStatusDetail()
        super.mouseExited(with: event)
    }

    private func cancelPendingSelectionCommit() {
        pendingSelectionWorkItem?.cancel()
        pendingSelectionWorkItem = nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func keyDown(with event: NSEvent) {
        if handleSelectionKeyCommand(event) { return }
        super.keyDown(with: event)
    }

    override func selectAll(_ sender: Any?) {
        interaction?.handleSelectAllFamiliesKeyCommand()
    }

    private func handleSelectionKeyCommand(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              event.charactersIgnoringModifiers?.lowercased() == "a",
              let interaction else { return false }
        if event.modifierFlags.contains(.shift) {
            interaction.handleSelectAllFontsDeepKeyCommand()
        } else if event.modifierFlags.contains(.option) {
            interaction.handleDeselectAllKeyCommand()
        } else {
            interaction.handleSelectAllFamiliesKeyCommand()
        }
        return true
    }

    override func mouseDown(with event: NSEvent) {
        cancelPendingSelectionCommit()
        mouseDownLocation = event.locationInWindow
        didBeginExportDrag = false
        dragVaultPath = nil
        dragFamilySection = nil
        pendingClick = nil
        pendingMouseDownEvent = nil

        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command),
           let interaction,
           interaction.tryOpenLink(at: point, in: self) {
            return
        }
        let chordClick = flags.contains(.command) || flags.contains(.shift)

        if row >= 0,
           let node = item(atRow: row) as? FontListOutlineNode,
           let interaction {
            if let section = node.familySection {
                dragFamilySection = section
                if event.clickCount >= 2 {
                    cancelPendingSelectionCommit()
                    interaction.handleFamilyRowDoubleClick(section: section, outlineView: self)
                    return
                }
                if isDisclosureTriangleClick(point: point, row: row) {
                    super.mouseDown(with: event)
                    return
                }
                window?.makeFirstResponder(self)
                if chordClick {
                    interaction.commitFamilyClick(section: section, event: event, outlineView: self)
                    return
                }
                pendingClick = .family(section)
                pendingMouseDownEvent = event
                return
            }
            if let path = node.vaultPath {
                dragVaultPath = path
                if event.clickCount >= 2 {
                    cancelPendingSelectionCommit()
                    interaction.handleFontRowDoubleClick(vaultPath: path, outlineView: self)
                    return
                }
                window?.makeFirstResponder(self)
                if chordClick {
                    interaction.commitFontClick(vaultPath: path, event: event, outlineView: self)
                    return
                }
                pendingClick = .font(path)
                pendingMouseDownEvent = event
                return
            }
        }

        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let click = pendingClick
        let downEvent = pendingMouseDownEvent
        defer {
            pendingClick = nil
            pendingMouseDownEvent = nil
        }

        if !didBeginExportDrag,
           event.clickCount == 1,
           let click,
           let downEvent,
           interaction != nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self, let interaction = self.interaction else { return }
                switch click {
                case .family(let section):
                    interaction.commitFamilyClick(section: section, event: downEvent, outlineView: self)
                case .font(let path):
                    interaction.commitFontClick(vaultPath: path, event: downEvent, outlineView: self)
                }
                self.pendingSelectionWorkItem = nil
            }
            pendingSelectionWorkItem = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + NSEvent.doubleClickInterval,
                execute: work
            )
        }

        super.mouseUp(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if pendingSelectionWorkItem != nil {
            cancelPendingSelectionCommit()
        }

        if !didBeginExportDrag,
           let interaction,
           interaction.shouldBeginExportDrag(from: mouseDownLocation, to: event.locationInWindow) {
            didBeginExportDrag = interaction.beginExportDrag(
                vaultPath: dragVaultPath,
                family: dragFamilySection,
                event: event,
                outlineView: self
            )
            if didBeginExportDrag { return }
        }

        if !didBeginExportDrag {
            super.mouseDragged(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        showContextMenu(for: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 {
            showContextMenu(for: event)
        } else {
            super.otherMouseDown(with: event)
        }
    }

    /// Clicks on the outline chevron expand/collapse only (FEX-style), not the family name.
    private func isDisclosureTriangleClick(point: NSPoint, row: Int) -> Bool {
        guard row >= 0, item(atRow: row) is FontListOutlineNode else { return false }
        guard let rowView = rowView(atRow: row, makeIfNecessary: true) else { return false }
        let local = convert(point, to: rowView)
        let level = level(forRow: row)
        let chevronMaxX = FontListOutlineChrome.disclosureHitMaxX(
            indentationPerLevel: indentationPerLevel,
            level: level
        )
        return local.x <= chevronMaxX
    }

    private func showContextMenu(for event: NSEvent) {
        if let menu = interaction?.contextMenu(for: event, outlineView: self) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

/// SwiftUI wrapper around virtualized `NSOutlineView` (FEX-style font list).
struct FontListOutlineHost: NSViewRepresentable {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: VaultSettings

    func makeCoordinator() -> FontListOutlineCoordinator {
        FontListOutlineCoordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        let outlineView = FontListOutlineView(frame: .zero)
        outlineView.style = .fullWidth
        outlineView.autosaveTableColumns = false
        outlineView.usesAlternatingRowBackgroundColors = true
        outlineView.intercellSpacing = NSSize(width: 0, height: 0)
        outlineView.rowSizeStyle = .custom
        outlineView.allowsMultipleSelection = true
        outlineView.allowsEmptySelection = true
        outlineView.columnAutoresizingStyle = .noColumnAutoresizing
        outlineView.focusRingType = .exterior
        outlineView.doubleAction = #selector(FontListOutlineCoordinator.outlineDoubleAction(_:))
        outlineView.registerForDraggedTypes([.fileURL])
        outlineView.setDraggingSourceOperationMask([], forLocal: true)
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)
        outlineView.interaction = context.coordinator

        context.coordinator.outlineView = outlineView
        context.coordinator.appState = appState
        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator
        outlineView.headerView = FontListOutlineHeaderView()
        (outlineView.headerView as? FontListOutlineHeaderView)?.interaction = context.coordinator

        scrollView.documentView = outlineView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(
            appState: appState,
            settings: settings,
            listDataRevision: appState.listDataRevision
        )
    }
}

extension FontListOutlineCoordinator {
    @objc func outlineDoubleAction(_ sender: Any?) {
        guard let outlineView = sender as? NSOutlineView ?? outlineView,
              outlineView.clickedRow >= 0,
              let node = outlineView.item(atRow: outlineView.clickedRow) as? FontListOutlineNode,
              let section = node.familySection else { return }
        handleFamilyRowDoubleClick(section: section, outlineView: outlineView)
    }
}
