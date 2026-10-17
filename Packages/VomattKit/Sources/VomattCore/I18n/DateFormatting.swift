import Foundation

/// The web's `features/polls/format.ts`, in the reader's language and time zone.
public struct DateFormatting: Sendable {
    public let language: Language
    public let timeZone: TimeZone

    public init(language: Language, timeZone: TimeZone = .current) {
        self.language = language
        self.timeZone = timeZone
    }

    private var locale: Locale { Locale(identifier: language.localeIdentifier) }

    /// "Oct 7, 22:00" / "10月7日 22:00"
    public func pollDate(_ date: Date) -> String {
        // Built from parts: iOS's own month-day-time pattern says "Oct 7 at 22:00"
        let day = formatter(template: "MMMd", timeZone: timeZone).string(from: date)
        let time = formatter(fixed: "HH:mm", timeZone: timeZone).string(from: date)
        return language == .zh ? "\(day) \(time)" : "\(day), \(time)"
    }

    /// "Aug 2026" / "2026年8月", in UTC so it matches the web.
    public func monthYear(_ date: Date) -> String {
        formatter(template: "MMMyyyy", timeZone: TimeZone(identifier: "UTC")!).string(from: date)
    }

    private func formatter(template: String? = nil, fixed: String? = nil, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        if let template { formatter.setLocalizedDateFormatFromTemplate(template) }
        if let fixed { formatter.dateFormat = fixed }
        return formatter
    }

    /// "in 5 hours" / "5 hours ago" / "5 小時前"
    public func fromNow(_ date: Date, now: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .numeric
        // Whole units, like date-fns' formatDistanceToNowStrict
        let seconds = date.timeIntervalSince(now)
        let magnitude = abs(seconds)
        var components = DateComponents()
        let sign = seconds < 0 ? -1 : 1
        switch magnitude {
        case ..<60: components.second = sign * Int(magnitude.rounded())
        case ..<3600: components.minute = sign * Int((magnitude / 60).rounded())
        case ..<86_400: components.hour = sign * Int((magnitude / 3600).rounded())
        case ..<(86_400 * 30): components.day = sign * Int((magnitude / 86_400).rounded())
        case ..<(86_400 * 365): components.month = sign * Int((magnitude / (86_400 * 30)).rounded())
        default: components.year = sign * Int((magnitude / (86_400 * 365)).rounded())
        }
        return formatter.localizedString(from: components)
    }
}
