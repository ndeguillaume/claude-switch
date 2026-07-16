import Foundation

/// Severity buckets for a usage percentage; the panel maps them to green/orange/red.
public enum UsageSeverity: Equatable {
    case normal
    case elevated
    case critical

    public init(percent: Int) {
        switch percent {
        case ..<70: self = .normal
        case ..<90: self = .elevated
        default: self = .critical
        }
    }
}

/// Formats a window reset date: time only when the reset falls today, weekday + time
/// otherwise (the weekly window resets days away, where a bare time would be ambiguous).
public enum ResetLabel {
    public static func text(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        } else {
            formatter.setLocalizedDateFormatFromTemplate("EEEjmm")
        }
        return formatter.string(from: date)
    }
}
