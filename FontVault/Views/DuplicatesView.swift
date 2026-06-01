import AppKit
import SwiftUI

struct DuplicatesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var moveRemovedToTrash = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if appState.isScanningDuplicates {
                Spacer()
                ProgressView("Scanning catalog for duplicate file content…")
                Spacer()
            } else if appState.duplicateGroups.isEmpty {
                emptyState
            } else {
                resultsList
                Divider()
                footer
            }
        }
        .onAppear {
            appState.ensureDuplicateScanForBrowse()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Duplicates")
                    .font(.headline)
                Text("Same file content (SHA-256), like FontExplorer X → Conflicts → Duplicates → File.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Scan") {
                appState.scanForDuplicates()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(appState.isScanningDuplicates)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(appState.duplicateScanCompleted
                ? "No duplicate file content found in the catalog."
                : "Click Scan to find fonts with identical file content.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(appState.duplicateGroups) { group in
                    duplicateCaseSection(group)
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func duplicateCaseSection(_ group: DuplicateGroup) -> some View {
        let keeper = appState.keeperPath(for: group)

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(group.displayTitle)
                    .font(.subheadline.weight(.semibold))
                Text("\(group.copyCount) copies")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("SHA \(group.sha256.prefix(8))…")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)

            HStack {
                Text("Keep").frame(width: 44, alignment: .leading)
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                Text("Format").frame(width: 56, alignment: .leading)
                Text("Import Date").frame(width: 88, alignment: .trailing)
                Text("Path").frame(width: 180, alignment: .leading)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)

            ForEach(group.fonts, id: \.vaultPath) { font in
                duplicateFontRow(font, group: group, isKeeper: font.vaultPath == keeper)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func duplicateFontRow(_ font: FontRecord, group: DuplicateGroup, isKeeper: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                appState.setKeeper(font.vaultPath, for: group.sha256)
            } label: {
                Image(systemName: isKeeper ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isKeeper ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 44, alignment: .leading)
            .help("Keep this copy")

            Text(font.fullName)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(FontFormat.from(pathExtension: font.format).badgeLabel)
                .font(.caption2)
                .frame(width: 56, alignment: .leading)

            Text(ImportDateDisplay.format(font.dateAdded))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .trailing)

            Text(font.vaultPath)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 180, alignment: .leading)
        }
        .padding(.vertical, 3)
        .background(isKeeper ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    private var footer: some View {
        HStack {
            Text("\(appState.duplicateGroups.count) duplicate cases · \(appState.duplicateFileCount) extra files")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Toggle("Move removed duplicates to Trash", isOn: $moveRemovedToTrash)
                .font(.caption)

            Button("Resolve Duplicates…") {
                appState.presentResolveDuplicates(moveToTrash: moveRemovedToTrash)
            }
            .disabled(appState.duplicateGroups.isEmpty)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
