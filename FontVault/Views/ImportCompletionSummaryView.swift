import SwiftUI

/// Structured import completion copy (progress sheet, detail sheet header, alerts).
struct ImportCompletionSummaryView: View {
    let report: ImportReport

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.controlSpacing + 2) {
            Text(report.importHeadline)
                .font(.body)
                .fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                statRow(label: "Scanned", value: report.scanned)
                statRow(
                    label: "Skipped",
                    value: report.skipped,
                    footnote: "Font files not copied (already in vault)"
                )
                statRow(label: "Failed", value: report.failedCount)
            }

            if report.ignoredFormatFileCount > 0 {
                Divider()
                    .padding(.vertical, 2)
                notImportedSection
            }

            if report.vaultFolderFallbackCount > 0 {
                Divider()
                    .padding(.vertical, 2)
                namingReviewSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notImportedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Not imported")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(
                "These were in the folder selection but never treated as font files to copy (not the same as Skipped)."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if report.ignoredUnsupported > 0 {
                statRow(label: "Unsupported type", value: report.ignoredUnsupported)
            }
            if report.ignoredFiltered > 0 {
                statRow(label: "Format filter", value: report.ignoredFiltered)
            }
        }
    }

    private var namingReviewSection: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.body)
                .foregroundStyle(.orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    "\(report.vaultFolderFallbackCount.formatted()) font\(report.vaultFolderFallbackCount == 1 ? "" : "s") copied, but vault folder used the file name instead of Full name."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if report.hasExportableIssueRows {
                    Text("Review in View Details — Save Review Package collects all flagged files and an HTML report.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func statRow(label: String, value: Int, footnote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(label) {
                Text(value.formatted())
                    .monospacedDigit()
            }
            .font(.callout)
            .labeledContentStyle(.automatic)

            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
