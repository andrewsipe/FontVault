import AppKit
import SwiftUI

// MARK: - Sidebar variable-font filter chip

/// Purple “VF” pill for Library → Format (filters variable fonts only).
struct FontVaultVariableFilterBadge: View {
    var body: some View {
        Text("VF")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.black)
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .frame(width: FontFormat.uniformBadgeWidth)
            .padding(.vertical, 3)
            .background(Color(nsColor: .systemPurple))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Format pill (sidebar + list)

/// Colored format pill shared by the sidebar and list (matches AppKit outline badges).
struct FontVaultFormatBadge: View {
    let format: FontFormat
    var isVariable: Bool = false
    var mixFormatExtensions: [String] = []

    var body: some View {
        let display = format.badgeLabel
        Text(display == "?" ? "—" : display)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foregroundColor(for: format))
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .frame(width: format == .unknown ? nil : FontFormat.uniformBadgeWidth)
            .padding(.vertical, 3)
            .background {
                badgeBackground(for: format)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func badgeBackground(for format: FontFormat) -> some View {
        if format == .mixed {
            let stops = FontFormat.mixGradientColors(fromExtensionStrings: mixFormatExtensions)
            if stops.count >= 2 {
                LinearGradient(
                    colors: stops.map { Color(nsColor: $0) },
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else if let solid = stops.first {
                Color(nsColor: solid)
            } else {
                Color(nsColor: format.badgeColors.background)
            }
        } else if isVariable, format.supportsVariableGradient {
            let background = format.badgeColors.background
            LinearGradient(
                colors: [
                    Color(nsColor: .systemPurple),
                    Color(nsColor: background),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            Color(nsColor: format.badgeColors.background)
        }
    }

    private func foregroundColor(for format: FontFormat) -> Color {
        Color(nsColor: format.badgeColors.foreground)
    }
}

// MARK: - Shared format badge styling

extension FontFormat {
    /// Stable left-to-right order for MIXED badge gradients.
    static let mixGradientDisplayOrder: [FontFormat] = [.otf, .ttf, .woff, .woff2, .ttc]

    /// File formats that can be variable fonts (gradient badge); collections use a solid chip.
    var supportsVariableGradient: Bool {
        switch self {
        case .otf, .ttf, .woff, .woff2:
            return true
        case .ttc, .mixed, .unknown:
            return false
        }
    }

    /// Sorted formats present in a family (for MIXED n-stop gradients).
    static func mixGradientFormats(fromExtensionStrings strings: [String]) -> [FontFormat] {
        let present = Set(
            strings
                .map { FontFormat.from(pathExtension: $0) }
                .filter { $0 != .unknown && $0 != .mixed }
        )
        return mixGradientDisplayOrder.filter { present.contains($0) }
    }

    static func mixGradientColors(fromExtensionStrings strings: [String]) -> [NSColor] {
        mixGradientFormats(fromExtensionStrings: strings).map(\.badgeColors.background)
    }

    static func mixedFormatsTooltip(fromExtensionStrings strings: [String]) -> String {
        let labels = mixGradientFormats(fromExtensionStrings: strings).map(\.badgeLabel)
        guard !labels.isEmpty else { return "MIXED" }
        return "Mixed formats: \(labels.joined(separator: ", "))"
    }
}

/// Applies format gradients or solid fills to an AppKit badge container.
enum FontFormatBadgeLayerStyle {
    private static let cornerRadius: CGFloat = 4

    static func apply(
        to container: NSView,
        format: FontFormat,
        isVariable: Bool,
        mixFormatExtensions: [String] = []
    ) {
        container.wantsLayer = true
        guard let layer = container.layer else { return }
        layer.cornerRadius = cornerRadius
        removeGradient(from: container)

        if format == .mixed {
            let colors = FontFormat.mixGradientColors(fromExtensionStrings: mixFormatExtensions)
            if colors.count >= 2 {
                applyGradient(to: container, colors: colors)
            } else if let solid = colors.first {
                layer.backgroundColor = solid.cgColor
            } else {
                layer.backgroundColor = format.badgeColors.background.cgColor
            }
            return
        }

        if isVariable, format.supportsVariableGradient {
            applyGradient(to: container, colors: [.systemPurple, format.badgeColors.background])
            return
        }

        layer.backgroundColor = format.badgeColors.background.cgColor
    }

    static func layoutGradient(in container: NSView) {
        container.layer?.sublayers?
            .first { $0.name == gradientLayerName }
            .map { $0.frame = container.bounds }
    }

    private static let gradientLayerName = "FontVaultFormatGradient"

    private static func applyGradient(to container: NSView, colors: [NSColor]) {
        guard let layer = container.layer else { return }
        layer.backgroundColor = nil
        let gradient = CAGradientLayer()
        gradient.name = gradientLayerName
        gradient.colors = colors.map(\.cgColor)
        let stopCount = colors.count
        if stopCount > 1 {
            gradient.locations = (0..<stopCount).map { index in
                NSNumber(value: Double(index) / Double(stopCount - 1))
            }
        }
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.cornerRadius = cornerRadius
        gradient.frame = container.bounds
        layer.insertSublayer(gradient, at: 0)
    }

    private static func removeGradient(from container: NSView) {
        container.layer?.sublayers?
            .filter { $0.name == gradientLayerName }
            .forEach { $0.removeFromSuperlayer() }
    }
}
