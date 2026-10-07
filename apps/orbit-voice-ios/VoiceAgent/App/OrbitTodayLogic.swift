import Foundation

nonisolated enum OrbitTodayLogic {
    // True when [start, end] touches the calendar day of `day`. Timed events use half-open end.
    static func overlapsDay(start: Date, end: Date, day: Date, calendar: Calendar = .current) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        let effectiveEnd = max(end, start)
        if effectiveEnd == start { return start >= dayStart && start < dayEnd }
        return start < dayEnd && effectiveEnd > dayStart
    }

    static func greeting(hour: Int, name: String?) -> String {
        let part: String
        switch hour {
        case 5..<12: part = "Доброго ранку"
        case 12..<18: part = "Доброго дня"
        case 18..<23: part = "Доброго вечора"
        default: part = "Доброї ночі"
        }
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return part }
        return "\(part), \(name)"
    }

    static func unreadLabel(_ count: Int) -> String {
        if count == 0 { return "Нових шкільних матеріалів немає" }
        let mod10 = count % 10, mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "\(count) нове шкільне повідомлення" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "\(count) нові шкільні повідомлення" }
        return "\(count) нових шкільних повідомлень"
    }
}
