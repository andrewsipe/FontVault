import AppKit

/// Open panel with format filters and copy/move (standard accessory view).
/// Prefilled from `VaultSettings`; choices apply to this import only (do not write back to Settings).
@MainActor
enum FontImportPanel {
    struct Result {
        var urls: [URL]
        var formats: ImportFormatOptions
        var operation: ImportFileOperation
    }

    static func pickFiles(
        initialFormats: ImportFormatOptions,
        initialOperation: ImportFileOperation
    ) -> Result? {
        let panel = NSOpenPanel()
        panel.title = "Import Fonts"
        panel.message = "Select font files or folders. Matching formats in subfolders are included."
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = true

        let accessory = ImportOptionsAccessoryView(
            formats: initialFormats,
            operation: initialOperation
        )
        accessory.frame = NSRect(x: 0, y: 0, width: 480, height: 132)
        panel.accessoryView = accessory
        panel.isAccessoryViewDisclosed = true
        applyContentTypes(panel, formats: initialFormats)
        accessory.onFormatsDidChange = { [weak panel] formats in
            guard let panel else { return }
            applyContentTypes(panel, formats: formats)
        }

        guard panel.runModal() == .OK else { return nil }
        guard accessory.formats.allowsAnyFontFile() else {
            showAlert(
                title: "No formats selected",
                message: "Choose at least one import format."
            )
            return nil
        }

        return Result(
            urls: panel.urls,
            formats: accessory.formats,
            operation: accessory.operation
        )
    }

    private static func applyContentTypes(_ panel: NSOpenPanel, formats: ImportFormatOptions) {
        let types = formats.allowedContentTypes()
        guard !types.isEmpty else { return }
        panel.allowedContentTypes = types
        panel.allowsOtherFileTypes = false
    }

    private static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

// MARK: - Accessory view

@MainActor
private final class ImportOptionsAccessoryView: NSView {
    var onFormatsDidChange: ((ImportFormatOptions) -> Void)?

    private(set) var formats: ImportFormatOptions
    private(set) var operation: ImportFileOperation

    private let openTypeButton = NSButton(
        checkboxWithTitle: "OpenType (.otf, .otc)",
        target: nil,
        action: nil
    )
    private let trueTypeButton = NSButton(
        checkboxWithTitle: "TrueType (.ttf, .ttc, .dfont)",
        target: nil,
        action: nil
    )
    private let webButton = NSButton(
        checkboxWithTitle: "Web fonts (.woff, .woff2)",
        target: nil,
        action: nil
    )
    private let copyRadio = NSButton(
        radioButtonWithTitle: ImportFileOperation.copy.label,
        target: nil,
        action: nil
    )
    private let moveRadio = NSButton(
        radioButtonWithTitle: ImportFileOperation.move.label,
        target: nil,
        action: nil
    )
    private let operationHint = NSTextField(wrappingLabelWithString: "")

    init(formats: ImportFormatOptions, operation: ImportFileOperation) {
        self.formats = formats
        self.operation = operation
        super.init(frame: .zero)
        buildUI()
        syncFromModel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        let formatsLabel = NSTextField(labelWithString: "Formats to import")
        formatsLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        for button in [openTypeButton, trueTypeButton, webButton] {
            button.target = self
            button.action = #selector(formatChanged(_:))
        }

        copyRadio.target = self
        copyRadio.action = #selector(operationChanged(_:))
        moveRadio.target = self
        moveRadio.action = #selector(operationChanged(_:))

        operationHint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        operationHint.textColor = .secondaryLabelColor
        operationHint.lineBreakMode = .byWordWrapping
        operationHint.maximumNumberOfLines = 0
        operationHint.preferredMaxLayoutWidth = 440

        let vaultLabel = NSTextField(labelWithString: "Into vault")
        vaultLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        let operationRow = NSStackView(views: [copyRadio, moveRadio])
        operationRow.orientation = .horizontal
        operationRow.spacing = 16

        let stack = NSStackView(views: [
            formatsLabel,
            openTypeButton,
            trueTypeButton,
            webButton,
            vaultLabel,
            operationRow,
            operationHint,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(10, after: webButton)
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
        openTypeButton.state = formats.openType ? .on : .off
        trueTypeButton.state = formats.trueType ? .on : .off
        webButton.state = formats.webFonts ? .on : .off
        copyRadio.state = operation == .copy ? .on : .off
        moveRadio.state = operation == .move ? .on : .off
        operationHint.stringValue = operation.detail
    }

    private func syncToModel() {
        formats.openType = openTypeButton.state == .on
        formats.trueType = trueTypeButton.state == .on
        formats.webFonts = webButton.state == .on
        operation = moveRadio.state == .on ? .move : .copy
        operationHint.stringValue = operation.detail
        onFormatsDidChange?(formats)
    }

    @objc private func formatChanged(_ sender: NSButton) {
        syncToModel()
    }

    @objc private func operationChanged(_ sender: NSButton) {
        if sender === copyRadio {
            copyRadio.state = .on
            moveRadio.state = .off
        } else {
            moveRadio.state = .on
            copyRadio.state = .off
        }
        syncToModel()
    }
}
