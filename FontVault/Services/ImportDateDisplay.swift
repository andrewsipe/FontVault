import Foundation

/// FEX-style import date labels for list and family headers.
enum ImportDateDisplay {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d/yy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func format(_ timestamp: TimeInterval) -> String {
        formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    /// Family row: one date when every style shares a calendar day; mixed when days differ.
    static func familyHeaderState(importDates: [TimeInterval]) -> FontFamilyFieldState {
        guard !importDates.isEmpty else { return .empty }

        let calendar = Calendar.current
        let dayKeys = Set(importDates.map { calendar.startOfDay(for: Date(timeIntervalSince1970: $0)) })
        if dayKeys.count == 1 {
            return .uniform(format(importDates[0]))
        }
        return .mixed
    }

    static func familyHeaderLabel(importDates: [TimeInterval]) -> String {
        familyHeaderState(importDates: importDates).tableText
    }

    /// Internal sentinel (ASCII hyphen); table UI uses `conflictDisplay`.
    static let conflictIndicator = "-"

    /// Shown in cells when values disagree or only some rows are populated.
    static let conflictDisplay = "—"
}
