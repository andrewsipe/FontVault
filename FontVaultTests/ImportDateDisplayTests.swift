import XCTest
@testable import FontVault

final class ImportDateDisplayTests: XCTestCase {
    func testFamilyHeaderShowsDashWhenDatesDiffer() {
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = Calendar.current.date(byAdding: .day, value: 3, to: day1)!
        let label = ImportDateDisplay.familyHeaderLabel(importDates: [
            day1.timeIntervalSince1970,
            day2.timeIntervalSince1970,
        ])
        XCTAssertEqual(label, ImportDateDisplay.conflictDisplay)
    }

    func testFamilyHeaderEmptyWhenNoDates() {
        XCTAssertEqual(ImportDateDisplay.familyHeaderLabel(importDates: []), "")
    }

    func testFamilyHeaderShowsDateWhenAllSameDay() {
        let noon = Date(timeIntervalSince1970: 1_700_000_000)
        let later = noon.addingTimeInterval(3600)
        let label = ImportDateDisplay.familyHeaderLabel(importDates: [
            noon.timeIntervalSince1970,
            later.timeIntervalSince1970,
        ])
        XCTAssertEqual(label, ImportDateDisplay.format(noon.timeIntervalSince1970))
    }
}
