import AppKit

/// Export destination and layout (family grouping, vault A–Z, or flat).
/// Prefilled from `VaultSettings`; layout applies to this export only (do not write back to Settings).
@MainActor
enum FontExportPanel {
    struct Result {
        var destination: URL
        var layoutMode: ExportLayoutMode
    }

    static func pickDestination(initialLayoutMode: ExportLayoutMode) -> Result? {
        let panel = NSOpenPanel()
        panel.title = "Export Fonts"
        panel.message = "Choose a folder. Selected fonts will be copied out of the vault."
        panel.prompt = "Export"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        let accessory = ExportOptionsAccessoryView(layoutMode: initialLayoutMode)
        accessory.frame = NSRect(x: 0, y: 0, width: 420, height: 88)
        panel.accessoryView = accessory
        panel.isAccessoryViewDisclosed = true

        guard panel.runModal() == .OK, let destination = panel.url else { return nil }

        return Result(
            destination: destination,
            layoutMode: accessory.layoutMode
        )
    }
}

@MainActor
private final class ExportOptionsAccessoryView: NSView {
    private(set) var layoutMode: ExportLayoutMode
    private var radioButtons: [ExportLayoutMode: NSButton] = [:]

    init(layoutMode: ExportLayoutMode) {
        self.layoutMode = layoutMode
        super.init(frame: .zero)
        buildUI()
        syncFromModel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        let title = NSTextField(labelWithString: "Export layout")
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        var optionViews: [NSView] = [title]

        for mode in ExportLayoutMode.allCases {
            let radio = NSButton(radioButtonWithTitle: mode.label, target: self, action: #selector(layoutChanged(_:)))
            radioButtons[mode] = radio
            optionViews.append(radio)
        }

        let stack = NSStackView(views: optionViews)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.setCustomSpacing(8, after: title)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    private func syncFromModel() {
        for (mode, button) in radioButtons {
            button.state = mode == layoutMode ? .on : .off
        }
    }

    @objc private func layoutChanged(_ sender: NSButton) {
        guard let mode = radioButtons.first(where: { $0.value === sender })?.key else { return }
        layoutMode = mode
        for (other, button) in radioButtons where other != mode {
            button.state = .off
        }
        sender.state = .on
    }
}
