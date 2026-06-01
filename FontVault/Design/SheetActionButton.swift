import SwiftUI

/// Consistent primary/secondary buttons for modal sheets (import progress, etc.).
enum SheetActionButton {
    /// Trailing a progress bar on the same row (FEX import sheet).
    static func primaryInline(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .fontVaultSheetInlinePrimaryButton()
    }

    static func secondaryInline(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(title, role: role, action: action)
            .fontVaultSheetInlineSecondaryButton()
    }

    /// Standalone footer row when not paired with a progress bar.
    static func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .fontVaultSheetPrimaryButton()
    }

    static func secondary(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(title, role: role, action: action)
            .fontVaultSheetSecondaryButton()
    }
}

private struct SheetActionButtonModifier: ViewModifier {
    enum Placement { case footer, inline }
    enum Kind { case primary, secondary }
    let placement: Placement
    let kind: Kind

    @ViewBuilder
    func body(content: Content) -> some View {
        switch (placement, kind) {
        case (.footer, .primary):
            content
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, DesignMetrics.sheetActionButtonHorizontalPadding)
                .frame(minWidth: DesignMetrics.sheetActionButtonMinWidth)
        case (.footer, .secondary):
            content
                .controlSize(.large)
                .buttonStyle(.bordered)
                .padding(.horizontal, DesignMetrics.sheetActionButtonHorizontalPadding)
                .frame(minWidth: DesignMetrics.sheetActionButtonMinWidth)
        case (.inline, .primary):
            content
                .controlSize(.regular)
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, DesignMetrics.sheetInlineActionHorizontalPadding)
                .fixedSize()
        case (.inline, .secondary):
            content
                .controlSize(.regular)
                .buttonStyle(.bordered)
                .padding(.horizontal, DesignMetrics.sheetInlineActionHorizontalPadding)
                .fixedSize()
        }
    }
}

extension View {
    func fontVaultSheetPrimaryButton() -> some View {
        modifier(SheetActionButtonModifier(placement: .footer, kind: .primary))
    }

    func fontVaultSheetSecondaryButton() -> some View {
        modifier(SheetActionButtonModifier(placement: .footer, kind: .secondary))
    }

    func fontVaultSheetInlinePrimaryButton() -> some View {
        modifier(SheetActionButtonModifier(placement: .inline, kind: .primary))
    }

    func fontVaultSheetInlineSecondaryButton() -> some View {
        modifier(SheetActionButtonModifier(placement: .inline, kind: .secondary))
    }
}
