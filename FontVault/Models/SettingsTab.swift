import Foundation

/// Signals the SwiftUI shell to present the Settings scene (`openSettings`).
struct SettingsOpenRequest: Equatable {
    let id = UUID()
    let tab: SettingsTab

    static func == (lhs: SettingsOpenRequest, rhs: SettingsOpenRequest) -> Bool {
        lhs.id == rhs.id
    }
}

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general
    case fontTable
    case inspector
    case vault

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .fontTable: return "Font Table"
        case .inspector: return "Information"
        case .vault: return "Vault"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .fontTable: return "tablecells"
        case .inspector: return "sidebar.right"
        case .vault: return "externaldrive"
        }
    }
}
