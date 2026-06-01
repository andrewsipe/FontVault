import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var selectionDisplay: ListSelectionDisplay

    var body: some View {
        VStack(spacing: 0) {
            inspectorToolbar
            Divider()
            Group {
                if !appState.selectedFamilyIDs.isEmpty || appState.selectedVaultPaths.count > 1 {
                    multiSelectionView
                } else if selectionDisplay.primaryFont != nil {
                    singleFontView
                } else {
                    emptyView
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var inspectorToolbar: some View {
        HStack {
            Text("Information")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                appState.openSettings(tab: .inspector)
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help("Choose which fields appear in Information (Settings)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var multiSelectionView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(
                    selectionDisplay.summary.isEmpty
                        ? "\(selectionDisplay.selectedFonts.count) fonts selected"
                        : selectionDisplay.summary
                )
                    .font(.headline)

                let totalSize = selectionDisplay.selectedFonts.reduce(Int64(0)) { $0 + $1.fileSize }
                Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Use the font table context menu or Font menu for export and remove actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var singleFontView: some View {
        Group {
            if let font = selectionDisplay.primaryFont {
                FontInspectorDetailBody(
                    font: font,
                    showAllCatalogFields: false,
                    showsHeader: true
                )
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No selection")
                .font(.headline)
            Text("Select a font in the table to view metadata.\nDouble-click a font row for the full inspector.\n⌘A families · ⇧⌘A all fonts · ⌥⌘A deselect.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
