import Foundation

enum OrbitSchoolDateDecoding {
    static func date(from value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }

        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

/// RFC5545 VALUE=DATE is a civil date, never a UTC instant to be displayed in
/// the device timezone. Keep it as a date-only value until formatting.
enum OrbitSchoolCivilDate {
    static func formatted(_ value: String, locale: Locale = Locale(identifier: "uk_UA")) -> String {
        guard let date = noonUTC(value) else { return value }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE, d MMM"
        return formatter.string(from: date)
    }

    static func inclusiveRange(start: String?, end: String?, locale: Locale = Locale(identifier: "uk_UA")) -> String {
        guard let start, !start.isEmpty else { return "Дата не визначена" }
        guard let end, !end.isEmpty, end != start else { return formatted(start, locale: locale) }
        return "\(formatted(start, locale: locale)) – \(formatted(end, locale: locale))"
    }

    private static let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }()

    private static func noonUTC(_ value: String) -> Date? {
        let parts = value.prefix(10).split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        return calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day, hour: 12))
    }
}
