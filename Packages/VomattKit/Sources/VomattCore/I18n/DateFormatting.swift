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
        let day = string(date, template: "MMMd", timeZone: timeZone)
        let time = string(date, fixed: "HH:mm", timeZone: timeZone)
        return language == .zh ? "\(day) \(time)" : "\(day), \(time)"
    }

    /// "Aug 2026" / "2026年8月", in UTC so it matches the web.
    public func monthYear(_ date: Date) -> String {
        string(date, template: "MMMyyyy", timeZone: TimeZone(identifier: "UTC")!)
    }

    /// "today" / "tomorrow" / "yesterday", the weekday within six days ("Fri"), else "Oct 24";
    /// zh 今天 / 週五 / 10月24日. Counts calendar days in the reader's time zone.
    public func pollDay(_ date: Date, now: Date = .now) -> String {
        let days = calendarDays(from: now, to: date)
        switch abs(days) {
        case 0, 1:
            let words = language == .zh ? ["昨天", "今天", "明天"] : ["yesterday", "today", "tomorrow"]
            return words[days + 1]
        case 2...6: return string(date, fixed: "EEE", timeZone: timeZone)
        default: return string(date, template: "MMMd", timeZone: timeZone)
        }
    }

    /// pollDay with the time: "today at 18:00", "Fri 20:00", "Oct 24, 20:00"; zh 今天 18:00 / 週五 20:00.
    public func pollMoment(_ date: Date, now: Date = .now) -> String {
        let day = pollDay(date, now: now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let clock = "\(parts.hour ?? 0):\(String(format: "%02d", parts.minute ?? 0))"
        if language == .zh { return "\(day) \(clock)" }
        let days = abs(calendarDays(from: now, to: date))
        if days <= 1 { return "\(day) at \(clock)" }
        return days <= 6 ? "\(day) \(clock)" : "\(day), \(clock)"
    }

    /// The largest whole unit, rounded, at least a minute: "45m", "6h", "2d"; zh 45 分鐘 / 6 小時 / 2 天.
    public func duration(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int((interval / 60).rounded()))
        if minutes < 60 { return unit(minutes, en: "m", zh: "分鐘") }
        // 59.6 minutes rounds up to "1h", not "60m"; the same at the day line
        let hours = Int((interval / 3600).rounded())
        if hours < 24 { return unit(hours, en: "h", zh: "小時") }
        return unit(Int((interval / 86_400).rounded()), en: "d", zh: "天")
    }

    /// A post's age for an author line: "now" (剛剛) under a minute, "45m", "2h", "3d", then "Oct 7".
    public func age(_ date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        switch seconds {
        case ..<60: return language == .zh ? "剛剛" : "now"
        case ..<3600: return unit(Int(seconds / 60), en: "m", zh: "分鐘")
        case ..<86_400: return unit(Int(seconds / 3600), en: "h", zh: "小時")
        case ..<(7 * 86_400): return unit(Int(seconds / 86_400), en: "d", zh: "天")
        default: return string(date, template: "MMMd", timeZone: timeZone)
        }
    }

    private func unit(_ value: Int, en: String, zh: String) -> String {
        language == .zh ? "\(value) \(zh)" : "\(value)\(en)"
    }

    private func calendarDays(from start: Date, to end: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }

    /// Cards call these for every poll on each minute tick, so each formatter is built once.
    private func string(_ date: Date, template: String? = nil, fixed: String? = nil, timeZone: TimeZone) -> String {
        let key = "\(language.localeIdentifier)|\(timeZone.identifier)|\(template ?? "")|\(fixed ?? "")"
        return Self.formatters.format(key) { () -> DateFormatter in
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            if let template { formatter.setLocalizedDateFormatFromTemplate(template) }
            if let fixed { formatter.dateFormat = fixed }
            return formatter
        } with: { $0.string(from: date) }
    }

    private static let formatters = FormatterCache()

    /// "in 5 hours" / "5 hours ago" / "5 小時前"
    public func fromNow(_ date: Date, now: Date = .now) -> String {
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
        return Self.formatters.format("\(language.localeIdentifier)|relative") { () -> RelativeDateTimeFormatter in
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = locale
            formatter.unitsStyle = .full
            formatter.dateTimeStyle = .numeric
            return formatter
        } with: { $0.localizedString(from: components) }
    }
}

/// Formatters built once per key. Not every Formatter is documented thread-safe, so each one is used under the lock.
private final class FormatterCache: @unchecked Sendable {
    private let lock = NSLock()
    private var formatters: [String: Formatter] = [:]

    func format<F: Formatter>(_ key: String, make: () -> F, with body: (F) -> String) -> String {
        lock.withLock {
            // A key names one formatter type, so the cast holds after the first build
            let formatter = formatters[key] as? F ?? make()
            formatters[key] = formatter
            return body(formatter)
        }
    }
}
