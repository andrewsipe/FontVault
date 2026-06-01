import AppKit

enum FontListContextMenuBuilder {
    @MainActor
    static func menu(for context: FontListContextMenuContext, target: FontListOutlineCoordinator) -> NSMenu {
        let menu = NSMenu()
        appendInspectorSection(to: menu, context: context, target: target)
        appendFileSection(to: menu, context: context, target: target)
        appendCopySection(to: menu, context: context, target: target)
        if context.urlIfValid != nil {
            menu.addItem(.separator())
            appendURLSection(to: menu, context: context, target: target)
        }
        if shouldShowFilterSection(context) {
            menu.addItem(.separator())
            _ = appendFilterSection(to: menu, context: context, target: target)
        }
        if context.canFind, let findText = context.findText {
            menu.addItem(.separator())
            appendFindSection(to: menu, findText: findText, target: target)
        }
        if context.hasMetadataIssues {
            menu.addItem(.separator())
            appendMetadataSection(to: menu, context: context, target: target)
        }
        if context.groupByFamily {
            menu.addItem(.separator())
            appendFamilySection(to: menu, target: target)
        }
        menu.addItem(.separator())
        appendEditSection(to: menu, target: target)
        if context.browserMode == .allFonts {
            menu.addItem(.separator())
            appendIndexSection(to: menu, context: context, target: target)
        }
        menu.addItem(.separator())
        appendDestructiveSection(to: menu, context: context, target: target)
        wireTargets(menu: menu, target: target, context: context)
        return menu
    }

    @MainActor
    private static func appendInspectorSection(
        to menu: NSMenu,
        context: FontListContextMenuContext,
        target: FontListOutlineCoordinator
    ) {
        menu.addItem(NSMenuItem(
            title: AppMenuCopy.openInInspectorWindow,
            action: #selector(FontListOutlineCoordinator.openInInspectorWindow),
            keyEquivalent: ""
        ))
        if context.showInspector {
            menu.addItem(NSMenuItem(
                title: AppMenuCopy.hideInInformation,
                action: #selector(FontListOutlineCoordinator.hideInInformation),
                keyEquivalent: ""
            ))
        } else {
            menu.addItem(NSMenuItem(
                title: AppMenuCopy.showInInformation,
                action: #selector(FontListOutlineCoordinator.showInInformation),
                keyEquivalent: ""
            ))
        }
        menu.addItem(.separator())
    }

    @MainActor
    private static func appendFileSection(
        to menu: NSMenu,
        context: FontListContextMenuContext,
        target: FontListOutlineCoordinator
    ) {
        menu.addItem(NSMenuItem(
            title: AppMenuCopy.revealInFinder,
            action: #selector(FontListOutlineCoordinator.revealInFinder),
            keyEquivalent: ""
        ))
        let exportItem = NSMenuItem(
            title: AppMenuCopy.exportFonts,
            action: #selector(FontListOutlineCoordinator.exportSelected),
            keyEquivalent: "e"
        )
        exportItem.keyEquivalentModifierMask = .command
        menu.addItem(exportItem)
    }

    @MainActor
    private static func appendCopySection(
        to menu: NSMenu,
        context: FontListContextMenuContext,
        target: FontListOutlineCoordinator
    ) {
        guard context.rowKind != .none else { return }
        let copyMenu = NSMenu(title: AppMenuCopy.copySubmenu)
        let copyParent = NSMenuItem(title: AppMenuCopy.copySubmenu, action: nil, keyEquivalent: "")
        copyParent.submenu = copyMenu

        if let column = context.clickedColumn {
            let uniqueCount = context.uniqueCount(for: .clickedColumn)
            let columnTitle: String
            if uniqueCount <= 1 {
                columnTitle = AppMenuCopy.copyColumn(column.title)
            } else {
                columnTitle = AppMenuCopy.copyColumnValues(column.title, uniqueCount: uniqueCount)
            }
            let columnItem = NSMenuItem(
                title: columnTitle,
                action: #selector(FontListOutlineCoordinator.performContextMenuCopy(_:)),
                keyEquivalent: ""
            )
            columnItem.representedObject = FontListContextMenuCopyKind.clickedColumn.rawValue
            columnItem.isEnabled = context.copyText(for: .clickedColumn) != nil
            copyMenu.addItem(columnItem)
        }

        copyMenu.addItem(
            copyItem(
                context: context,
                kind: .fontName,
                singular: AppMenuCopy.copyFontName,
                plural: AppMenuCopy.copyFontNames
            )
        )
        copyMenu.addItem(
            copyItem(
                context: context,
                kind: .fontFamily,
                singular: AppMenuCopy.copyFontFamily,
                plural: AppMenuCopy.copyFontFamilies
            )
        )
        copyMenu.addItem(
            copyItem(
                context: context,
                kind: .fullPath,
                singular: AppMenuCopy.copyFullPath,
                plural: AppMenuCopy.copyFullPaths
            )
        )

        if context.isFamilyHeaderRow, context.familySection != nil {
            let familyRowItem = NSMenuItem(
                title: AppMenuCopy.copyFamilyRow,
                action: #selector(FontListOutlineCoordinator.performContextMenuCopy(_:)),
                keyEquivalent: ""
            )
            familyRowItem.representedObject = FontListContextMenuCopyKind.familyHeaderRow.rawValue
            familyRowItem.isEnabled = context.copyText(for: .familyHeaderRow) != nil
            copyMenu.addItem(familyRowItem)
        }

        if !context.fontsForFontRowCopy.isEmpty {
            let count = context.fontRowCopyCount
            let rowsTitle = count <= 1 ? AppMenuCopy.copyRow : AppMenuCopy.copyRows(count)
            let rowsItem = NSMenuItem(
                title: rowsTitle,
                action: #selector(FontListOutlineCoordinator.performContextMenuCopy(_:)),
                keyEquivalent: ""
            )
            rowsItem.representedObject = FontListContextMenuCopyKind.fontRows.rawValue
            rowsItem.isEnabled = context.copyText(for: .fontRows) != nil
            copyMenu.addItem(rowsItem)
        }

        menu.addItem(copyParent)
    }

    @MainActor
    private static func copyItem(
        context: FontListContextMenuContext,
        kind: FontListContextMenuCopyKind,
        singular: String,
        plural: (Int) -> String
    ) -> NSMenuItem {
        let uniqueCount = context.uniqueCount(for: kind)
        let title = context.copyMenuTitle(singular: singular, plural: plural, uniqueCount: uniqueCount)
        let item = NSMenuItem(
            title: title,
            action: #selector(FontListOutlineCoordinator.performContextMenuCopy(_:)),
            keyEquivalent: ""
        )
        item.representedObject = kind.rawValue
        item.isEnabled = context.copyText(for: kind) != nil
        return item
    }

    @MainActor
    private static func appendURLSection(
        to menu: NSMenu,
        context: FontListContextMenuContext,
        target: FontListOutlineCoordinator
    ) {
        menu.addItem(NSMenuItem(
            title: AppMenuCopy.openURL,
            action: #selector(FontListOutlineCoordinator.performContextMenuAction(_:)),
            keyEquivalent: ""
        ).configured(representedObject: FontListContextMenuActionKind.openURL.rawValue))

        let copyURL = NSMenuItem(
            title: AppMenuCopy.copyURL,
            action: #selector(FontListOutlineCoordinator.performContextMenuAction(_:)),
            keyEquivalent: ""
        )
        copyURL.representedObject = FontListContextMenuActionKind.copyURL.rawValue
        copyURL.isEnabled = context.urlIfValid != nil
        menu.addItem(copyURL)
    }

    @MainActor
    private static func shouldShowFilterSection(_ context: FontListContextMenuContext) -> Bool {
        !context.formatFilterMenuOptions.isEmpty
            || context.showsClearFormatFilter
            || context.showsExcludedFontsSmartFilter
    }

    @discardableResult
    private static func appendFilterSection(
        to menu: NSMenu,
        context: FontListContextMenuContext,
        target: FontListOutlineCoordinator
    ) -> Bool {
        let filterMenu = NSMenu(title: AppMenuCopy.filterSubmenu)
        let filterParent = NSMenuItem(title: AppMenuCopy.filterSubmenu, action: nil, keyEquivalent: "")
        filterParent.submenu = filterMenu

        for option in context.formatFilterMenuOptions {
            let item = NSMenuItem(
                title: AppMenuCopy.showOnlyFormat(option.badgeLabel),
                action: #selector(FontListOutlineCoordinator.performContextMenuAction(_:)),
                keyEquivalent: ""
            )
            item.representedObject = FontListContextMenuActionKind.showOnlyFormatKey(option.filterKey)
            filterMenu.addItem(item)
        }

        if context.showsClearFormatFilter {
            if !context.formatFilterMenuOptions.isEmpty {
                filterMenu.addItem(.separator())
            }
            filterMenu.addItem(NSMenuItem(
                title: AppMenuCopy.clearFormatFilter,
                action: #selector(FontListOutlineCoordinator.performContextMenuAction(_:)),
                keyEquivalent: ""
            ).configured(representedObject: FontListContextMenuActionKind.clearFormatFilter.rawValue))
        }

        if context.showsExcludedFontsSmartFilter {
            if !filterMenu.items.isEmpty {
                filterMenu.addItem(.separator())
            }
            filterMenu.addItem(NSMenuItem(
                title: AppMenuCopy.showOnlySmartFilter(AppMenuCopy.smartFilterExcludedFonts),
                action: #selector(FontListOutlineCoordinator.performContextMenuAction(_:)),
                keyEquivalent: ""
            ).configured(representedObject: FontListContextMenuActionKind.smartFilterExcludedFonts.rawValue))
        }

        guard !filterMenu.items.isEmpty else { return false }
        menu.addItem(filterParent)
        return true
    }

    @MainActor
    private static func appendFindSection(
        to menu: NSMenu,
        findText: String,
        target: FontListOutlineCoordinator
    ) {
        menu.addItem(NSMenuItem(
            title: AppMenuCopy.findValue(findText),
            action: #selector(FontListOutlineCoordinator.performContextMenuAction(_:)),
            keyEquivalent: ""
        ).configured(representedObject: FontListContextMenuActionKind.find.rawValue))
    }

    @MainActor
    private static func appendMetadataSection(
        to menu: NSMenu,
        context: FontListContextMenuContext,
        target: FontListOutlineCoordinator
    ) {
        let metadataMenu = NSMenu(title: AppMenuCopy.metadataSubmenu)
        let metadataParent = NSMenuItem(title: AppMenuCopy.metadataSubmenu, action: nil, keyEquivalent: "")
        metadataParent.submenu = metadataMenu

        if context.showInspector {
            metadataMenu.addItem(NSMenuItem(
                title: AppMenuCopy.hideInInformation,
                action: #selector(FontListOutlineCoordinator.hideInInformation),
                keyEquivalent: ""
            ))
        } else {
            metadataMenu.addItem(NSMenuItem(
                title: AppMenuCopy.showIssueInInformation,
                action: #selector(FontListOutlineCoordinator.showMetadataIssueInInformation),
                keyEquivalent: ""
            ))
        }
        let summaryItem = NSMenuItem(
            title: AppMenuCopy.copyIssueSummary,
            action: #selector(FontListOutlineCoordinator.copyMetadataIssueSummary),
            keyEquivalent: ""
        )
        summaryItem.isEnabled = context.metadataIssueSummary() != nil
        metadataMenu.addItem(summaryItem)

        menu.addItem(metadataParent)
    }

    @MainActor
    private static func appendFamilySection(to menu: NSMenu, target: FontListOutlineCoordinator) {
        menu.addItem(NSMenuItem(
            title: AppMenuCopy.expandAllFamilies,
            action: #selector(FontListOutlineCoordinator.expandAllFamilies),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: AppMenuCopy.collapseAllFamilies,
            action: #selector(FontListOutlineCoordinator.collapseAllFamilies),
            keyEquivalent: ""
        ))
    }

    @MainActor
    private static func appendEditSection(to menu: NSMenu, target: FontListOutlineCoordinator) {
        menu.addItem(NSMenuItem(title: AppMenuCopy.selectAllFamilies, action: #selector(FontListOutlineCoordinator.selectAllFamilies), keyEquivalent: "a"))
        menu.addItem(NSMenuItem(title: AppMenuCopy.selectAllFonts, action: #selector(FontListOutlineCoordinator.selectAllFontsDeep), keyEquivalent: "a"))
        menu.addItem(NSMenuItem(title: AppMenuCopy.deselectAll, action: #selector(FontListOutlineCoordinator.deselectAll), keyEquivalent: "a"))
    }

    @MainActor
    private static func appendIndexSection(
        to menu: NSMenu,
        context: FontListContextMenuContext,
        target: FontListOutlineCoordinator
    ) {
        menu.addItem(NSMenuItem(
            title: AppMenuCopy.excludeFromIndex,
            action: #selector(FontListOutlineCoordinator.excludeFromIndex),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: AppMenuCopy.includeInIndex,
            action: #selector(FontListOutlineCoordinator.includeInIndex),
            keyEquivalent: ""
        ))
    }

    @MainActor
    private static func appendDestructiveSection(
        to menu: NSMenu,
        context: FontListContextMenuContext,
        target: FontListOutlineCoordinator
    ) {
        menu.addItem(NSMenuItem(title: AppMenuCopy.moveToTrash, action: #selector(FontListOutlineCoordinator.removeToTrash), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: AppMenuCopy.deleteImmediately, action: #selector(FontListOutlineCoordinator.deleteImmediately), keyEquivalent: ""))
    }

    @MainActor
    private static func wireTargets(
        menu: NSMenu,
        target: FontListOutlineCoordinator,
        context: FontListContextMenuContext
    ) {
        let hasSelection = context.selectionCount > 0
        for item in menu.items {
            item.target = target
            if let submenu = item.submenu {
                for sub in submenu.items {
                    sub.target = target
                }
            }
            if item.action == #selector(FontListOutlineCoordinator.selectAllFamilies) {
                item.keyEquivalentModifierMask = .command
            } else if item.action == #selector(FontListOutlineCoordinator.selectAllFontsDeep) {
                item.keyEquivalentModifierMask = [.command, .shift]
            } else if item.action == #selector(FontListOutlineCoordinator.deselectAll) {
                item.keyEquivalentModifierMask = [.command, .option]
            }
        }

        for item in menu.items where item.action == #selector(FontListOutlineCoordinator.deselectAll)
            || item.action == #selector(FontListOutlineCoordinator.revealInFinder)
            || item.action == #selector(FontListOutlineCoordinator.exportSelected)
            || item.action == #selector(FontListOutlineCoordinator.excludeFromIndex)
            || item.action == #selector(FontListOutlineCoordinator.includeInIndex)
            || item.action == #selector(FontListOutlineCoordinator.removeToTrash)
            || item.action == #selector(FontListOutlineCoordinator.deleteImmediately) {
            item.isEnabled = hasSelection
        }

        for item in menu.items {
            wireSubmenuTargets(item, target: target)
        }

        guard let appState = target.appStateForMenu else { return }
        if let excludeItem = menu.items.first(where: { $0.action == #selector(FontListOutlineCoordinator.excludeFromIndex) }) {
            excludeItem.isEnabled = hasSelection && appState.canExcludeSelectionFromIndex
        }
        if let includeItem = menu.items.first(where: { $0.action == #selector(FontListOutlineCoordinator.includeInIndex) }) {
            includeItem.isEnabled = hasSelection && appState.canIncludeSelectionInIndex
        }
        if let inspectorItem = menu.items.first(where: { $0.action == #selector(FontListOutlineCoordinator.openInInspectorWindow) }) {
            inspectorItem.isEnabled = appState.canPresentFontInspectorForSelection
        }
    }

    @MainActor
    private static func wireSubmenuTargets(_ item: NSMenuItem, target: FontListOutlineCoordinator) {
        item.target = target
        item.submenu?.items.forEach { wireSubmenuTargets($0, target: target) }
    }
}

private extension NSMenuItem {
    func configured(representedObject: String) -> NSMenuItem {
        self.representedObject = representedObject
        return self
    }
}
