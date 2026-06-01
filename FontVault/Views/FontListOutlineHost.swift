import AppKit
import SwiftUI

/// Column header that receives right-click (events do not reach `NSOutlineView`).
final class FontListOutlineHeaderView: NSTableHeaderView {
    weak var interaction: FontListOutlineCoordinator?

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
