import SwiftUI

/// Font catalog list — AppKit `NSOutlineView` (virtualized, FEX-aligned).
struct FontListView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = VaultSettings.shared

    var body: some View {
        FontListOutlineHost(appState: appState, settings: settings)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .fontVaultDropTarget()
    }
}
