import Foundation

/// Resolved text and adornments for a single table cell.
struct FontListCellPresentation: Equatable, Sendable {
    var text: String
    /// Orange underline on this column’s text when metadata needs attention.
    var showsMetadataAttention: Bool = false
    var metadataWarningDetail: String?
    /// Blue link styling for URL columns (distinct from metadata attention).
    var showsLink: Bool = false
    var linkURL: URL?

    static let empty = FontListCellPresentation(text: "")

    /// Applies link styling when this column holds a valid http(s) URL and the cell is not flagged for metadata.
    func applyingLinkStyleIfNeeded(column: FontListColumn) -> FontListCellPresentation {
        guard !showsMetadataAttention,
              column.isWebURLColumn,
              let url = FontListURLParsing.validHTTPURL(from: text)
        else { return self }
        var copy = self
        copy.showsLink = true
        copy.linkURL = url
        return copy
    }

    var toolTipText: String? {
        text.isEmpty ? nil : text
    }

    var metadataWarningToolTip: String? {
        guard showsMetadataAttention, let metadataWarningDetail, !metadataWarningDetail.isEmpty else {
            return nil
        }
        return metadataWarningDetail
    }
}

extension FontFamilyFieldState {
    func cellPresentation(columnTitle: String) -> FontListCellPresentation {
        switch self {
        case .empty:
            return .empty
        case .uniform(let value):
            return FontListCellPresentation(text: value)
        case .mixed:
            return FontListCellPresentation(text: ImportDateDisplay.conflictDisplay)
        case .derived(let value, _):
            return FontListCellPresentation(text: value)
        case .flagged(let value, let issues):
            let active = MetadataIssue.userFacing(issues)
            guard !active.isEmpty else {
                return FontListCellPresentation(text: value)
            }
            return FontListCellPresentation(
                text: value,
                showsMetadataAttention: true,
                metadataWarningDetail: MetadataIssue.metadataWarningTooltip(
                    columnTitle: columnTitle,
                    issues: active
                )
            )
        }
    }

    var cellPresentation: FontListCellPresentation {
        cellPresentation(columnTitle: "")
    }
}
