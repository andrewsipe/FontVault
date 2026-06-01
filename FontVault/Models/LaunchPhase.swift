import Foundation

/// Application launch gate (FEX-style splash before main library UI).
enum LaunchPhase: Equatable {
    case idle
    case openingCatalog
    case preparingList
    case ready
    case failed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isInProgress: Bool {
        switch self {
        case .openingCatalog, .preparingList: return true
        default: return false
        }
    }
}
