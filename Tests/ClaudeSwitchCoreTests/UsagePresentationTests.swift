import XCTest
@testable import ClaudeSwitchCore

final class UsagePresentationTests: XCTestCase {
    func testSeverityBuckets() {
        XCTAssertEqual(UsageSeverity(percent: 0), .normal)
        XCTAssertEqual(UsageSeverity(percent: 69), .normal)
        XCTAssertEqual(UsageSeverity(percent: 70), .elevated)
        XCTAssertEqual(UsageSeverity(percent: 89), .elevated)
        XCTAssertEqual(UsageSeverity(percent: 90), .critical)
        XCTAssertEqual(UsageSeverity(percent: 130), .critical)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    func testResetLabelSameDayShowsTimeOnly() {
        let label = ResetLabel.text(
            for: date("2026-07-13T18:30:00Z"),
            now: date("2026-07-13T10:00:00Z"),
            calendar: utcCalendar,
            locale: Locale(identifier: "fr_FR")
        )
        XCTAssertEqual(label, "18:30")
    }

    func testResetLabelOtherDayShowsWeekdayAndTime() {
        let label = ResetLabel.text(
            for: date("2026-07-15T09:00:00Z"),
            now: date("2026-07-13T10:00:00Z"),
            calendar: utcCalendar,
            locale: Locale(identifier: "fr_FR")
        )
        XCTAssertTrue(label.localizedCaseInsensitiveContains("mer"), "attendu un jour de semaine, obtenu : \(label)")
        XCTAssertTrue(label.contains("09:00"), "attendu l'heure, obtenu : \(label)")
    }

    func testResetLabelMidnightBoundaryIsNotSameDay() {
        let label = ResetLabel.text(
            for: date("2026-07-14T00:05:00Z"),
            now: date("2026-07-13T23:50:00Z"),
            calendar: utcCalendar,
            locale: Locale(identifier: "fr_FR")
        )
        XCTAssertTrue(label.localizedCaseInsensitiveContains("mar"), "attendu un jour de semaine, obtenu : \(label)")
    }
}
