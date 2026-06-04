import AppKit
import SwiftUI

@main
struct FontVaultApp: App {
    @StateObject private var appState = AppState()
    @ObservedObject private var settings = VaultSettings.shared
    @ObservedObject private var inspectorCommands = FontInspectorCommandState.shared

    init() {
        // Single-window app: no document tabs — hides "Show Tab Bar" / "Show All Tabs" in View.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(appState.selectionDisplay)
                .frame(minWidth: 960, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .windowArrangement) {
                Button(AppMenuCopy.inspectorPreviousTab) {
                    FontInspectorWindowController.shared.stepKeyWindowTab(by: -1)
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(!inspectorCommands.canStepTabBack)

                Button(AppMenuCopy.inspectorNextTab) {
                    FontInspectorWindowController.shared.stepKeyWindowTab(by: 1)
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(!inspectorCommands.canStepTabForward)
            }

            CommandGroup(after: .importExport) {
                Button(settings.importMenuTitle) {
                    appState.presentImportPanel()
                }
                .keyboardShortcut("i", modifiers: .command)

                Button(AppMenuCopy.exportFonts) {
                    appState.presentExportSelected()
                }
                .keyboardShortcut("e", modifiers: .command)
            }

            CommandGroup(after: .pasteboard) {
                Button(AppMenuCopy.selectAllFamilies) {
                    appState.selectAllFamiliesInFilter()
                }
                .keyboardShortcut("a", modifiers: .command)

                Button(AppMenuCopy.selectAllFonts) {
                    appState.selectAllFontsDeepInFilter()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Button(AppMenuCopy.deselectAll) {
                    appState.deselectAll()
                }
                .keyboardShortcut("a", modifiers: [.command, .option])

                Divider()

                Button(AppMenuCopy.find) {
                    appState.performFindFromList()
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            // View menu: library, information, counters, list layout (replaces system sidebar + tab bar items).
            CommandGroup(replacing: .sidebar) {
                Button(appState.prefersSidebarVisible ? AppMenuCopy.hideLibrary : AppMenuCopy.showLibrary) {
                    appState.toggleSidebarVisibility()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])

                Button(appState.showInspector ? AppMenuCopy.hideInformation : AppMenuCopy.showInformation) {
                    appState.toggleInspectorVisibility()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])

                Button(settings.showLibraryCounters ? AppMenuCopy.hideCounters : AppMenuCopy.showCounters) {
                    settings.showLibraryCounters.toggle()
                }

                Divider()

                Button(settings.showIgnoredFonts ? AppMenuCopy.hideIgnoredFonts : AppMenuCopy.showIgnoredFonts) {
                    appState.toggleShowIgnoredFonts()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Toggle(AppMenuCopy.excludeIgnoredFontsFromIndex, isOn: $settings.excludeIgnoredFontsFromIndex)

                Button(settings.showMetadataWarnings ? AppMenuCopy.hideMetadataWarnings : AppMenuCopy.showMetadataWarnings) {
                    appState.toggleShowMetadataWarnings()
                }

                Divider()

                Toggle(AppMenuCopy.groupByFamily, isOn: $appState.groupByFamily)
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(appState.browserMode != .allFonts)

                Button(AppMenuCopy.resetListSortToDefault) {
                    appState.resetListSortToDefault()
                }
                .disabled(appState.browserMode != .allFonts)

                Divider()

                Button(AppMenuCopy.fontTable) {
                    appState.openSettings(tab: .fontTable)
                }
            }

            CommandMenu("Font") {
                Button(AppMenuCopy.excludeFromIndex) {
                    appState.presentExcludeSelectedFromIndex()
                }
                .disabled(!appState.canExcludeSelectionFromIndex)

                Button(AppMenuCopy.includeInIndex) {
                    appState.includeSelectedInIndex()
                }
                .disabled(!appState.canIncludeSelectionInIndex)

                Divider()

                Button(AppMenuCopy.moveToTrash) {
                    appState.presentRemoveSelected(moveToTrash: true)
                }
                .keyboardShortcut(.delete, modifiers: [])

                Button(AppMenuCopy.deleteImmediately) {
                    appState.presentRemoveSelected(moveToTrash: false)
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .help) {
                Button("Font Vault Help…") {
                    VaultOrganizationHelp.presentHelpAlert()
                }
            }

            CommandMenu("Vault") {
                Button(settings.catalogScanMenuTitle) {
                    appState.indexVault()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                if settings.organizesVaultFiles {
                    Button(AppMenuCopy.reorganizeLayout) {
                        appState.reorganizeVault()
                    }
                }

                Divider()

                Button(AppMenuCopy.cleanVault) {
                    appState.presentCleanVault()
                }

                Divider()

                Button(AppMenuCopy.findDuplicates) {
                    appState.showDuplicates()
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
