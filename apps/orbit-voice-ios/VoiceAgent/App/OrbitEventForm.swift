import SwiftUI

// One event form for every place that creates, edits or shows an event (owner request 2026-11-18): the same sections and fields everywhere.
// A field that this place cannot change stays visible but gray (disabled), with a short reason, instead of disappearing.

/// What the current place lets the user change. `true` = editable; `false` = shown gray.
struct OrbitEventFormAvailability: Equatable {
    var title = true
    var notes = true
    var location = true
    var allDay = true
    var time = true
    /// Why the place is gray (e.g. only iCloud events carry a place); shown under the field when it is not editable.
    var locationNote: String? = nil

    static let all = OrbitEventFormAvailability()
    /// Everything gray: the event comes from the school calendar and is added exactly as the school published it.
    static let readOnly = OrbitEventFormAvailability(title: false, notes: false, location: false, allDay: false, time: false)
}

/// The values every event form edits.
struct OrbitEventFormValues: Equatable {
    var title = ""
    var notes = ""
    var location = ""
    var allDay = false
    var startsAt = Date().addingTimeInterval(3600)
    var endsAt = Date().addingTimeInterval(7200)
}

/// The shared sections "Подія" and "Час".
struct OrbitEventDetailSections: View {
    @Binding var values: OrbitEventFormValues
    var availability: OrbitEventFormAvailability = .all

    private var components: DatePickerComponents { values.allDay ? [.date] : [.date, .hourAndMinute] }

    var body: some View {
        Section("Подія") {
            TextField("Назва", text: $values.title).disabled(!availability.title)
            TextField("Нотатки", text: $values.notes, axis: .vertical).disabled(!availability.notes)
            TextField("Місце", text: $values.location).disabled(!availability.location)
            if !availability.location, let note = availability.locationNote {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
            Toggle("Весь день", isOn: $values.allDay).disabled(!availability.allDay)
        }
        Section("Час") {
            DatePicker("Початок", selection: $values.startsAt, displayedComponents: components).disabled(!availability.time)
            DatePicker("Кінець", selection: $values.endsAt, in: values.startsAt..., displayedComponents: components).disabled(!availability.time)
        }
    }
}

extension OrbitEventFormValues {
    /// A School letter event (Europe/Berlin wall time is applied by the form's time zone environment).
    init(schoolEvent event: OrbitSchoolEvent) {
        let start = event.startsAt ?? Date().addingTimeInterval(3600)
        self.init(title: event.title, notes: "", location: event.location ?? "", allDay: event.allDay, startsAt: start, endsAt: max(event.endsAt ?? start.addingTimeInterval(3600), start))
    }

    /// A School calendar (Schulmanager) event: ISO date-time, or a plain date for all-day events.
    init(schulmanagerEvent event: OrbitSchulmanagerCalendarEvent) {
        let start = Self.parse(event.startsAt) ?? Date()
        let end = Self.parse(event.endsAt) ?? start.addingTimeInterval(3600)
        self.init(title: event.title, notes: event.description, location: event.location, allDay: event.allDay, startsAt: start, endsAt: max(end, start))
    }

    private static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: raw) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = SchoolHubLogic.schoolTimeZone
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: String(raw.prefix(10)))
    }
}

extension OrbitSchoolEvent {
    /// A copy with the user's edits (the server takes title/time/place from the request body).
    init(key: String, title: String, startsAt: Date?, endsAt: Date?, allDay: Bool, location: String?) {
        self.key = key
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.allDay = allDay
        self.location = location
    }
}
