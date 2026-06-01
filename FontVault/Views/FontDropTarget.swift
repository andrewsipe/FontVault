import SwiftUI
import UniformTypeIdentifiers

/// External import only when organization is on — ignores export drags from the font list (FEX-style).
struct FontVaultDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let appState: AppState

    func validateDrop(info: DropInfo) -> Bool {
        if !VaultSettings.shared.organizesVaultFiles { return false }
        if appState.isExportDragInProgress { return false }
        if FontVaultDragTypes.isExportDragOnDragPasteboard() { return false }
        return true
    }

    func dropEntered(info: DropInfo) {
        isTargeted = validateDrop(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if validateDrop(info: info) {
            return DropProposal(operation: .copy)
        }
        isTargeted = false
        return DropProposal(operation: .forbidden)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard validateDrop(info: info) else { return false }

        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }

        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await FontDropTarget.loadFileURL(from: provider) {
                    urls.append(url)
                }
            }
            if !urls.isEmpty {
                await appState.importDroppedURLs(urls)
            }
        }
        return true
    }
}

/// Drag-and-drop font files or folders from Finder onto the main window.
struct FontDropTarget: ViewModifier {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = VaultSettings.shared
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .background(Color.accentColor.opacity(0.08))
                        .padding(8)
                        .allowsHitTesting(false)
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.largeTitle)
                        Text("Drop fonts or folders to import")
                            .font(.headline)
                    }
                    .allowsHitTesting(false)
                }
            }
            .onDrop(
                of: [.fileURL],
                delegate: FontVaultDropDelegate(isTargeted: $isTargeted, appState: appState)
            )
    }

    static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data,
                          let path = String(data: data, encoding: .utf8),
                          let url = URL(string: path) {
                    continuation.resume(returning: url)
                } else if let path = item as? String {
                    continuation.resume(returning: URL(fileURLWithPath: path))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

extension View {
    func fontVaultDropTarget() -> some View {
        modifier(FontDropTarget())
    }
}
