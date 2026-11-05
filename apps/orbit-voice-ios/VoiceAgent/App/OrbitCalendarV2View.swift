import SwiftUI

/// Stable navigation owner. The authored ROUTES 05 concept is implemented by
/// the live view below so existing Main Orbit navigation keeps its contract.
struct OrbitCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    var origin: OrbitCalendarRouteOrigin = .root

    var body: some View {
        OrbitCalendarV2View(onBack: origin.showsBackControl ? { dismiss() } : nil)
    }
}

// ORBIT FAMILY AI — Calendar ROUTES 05 live implementation.
// The hierarchy and geometry are intentionally carried over from the supplied
// SwiftUI concept; data and mutations come from MainProductAPI only.

struct OrbitCalendarV2View: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    private let calendar = ConceptCalendarDates.calendar
    private let debugFixtureMode: Bool
    private let debugDetailMode: Bool

    @State private var referenceDate: Date
    @State private var visibleMonth: Date
    @State private var weekAnchor: Date
    @State private var displayMode: OrbitCalendarV2Logic.DisplayMode = .week
    @State private var selectedDate: Date?
    @State private var sources: [ConceptCalendarSource] = []
    @State private var enabledSourceIDs: Set<String> = []
    @State private var events: [ConceptCalendarEvent] = []
    @State private var liveEvents: [OrbitCalendarEvent] = []
    @State private var people: [ConceptCalendarPerson] = []
    @State private var coverageText: String?
    @State private var coverageComplete = false
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var showingSources = false
    @State private var showingCreator = false
    @State private var selectedEvent: ConceptCalendarEvent?
    @State private var editingEvent: OrbitCalendarEvent?

    @State private var draftTitle = ""
    @State private var draftDate = Date.now
    @State private var draftAllDay = false
    @State private var draftInvolvedIDs: Set<String> = []

    private let onBack: (() -> Void)?

    init(referenceDate: Date = .now, onBack: (() -> Void)? = nil) {
        self.onBack = onBack
        #if DEBUG
        debugFixtureMode = ProcessInfo.processInfo.arguments.contains("--routes05-calendar-fixture") || ProcessInfo.processInfo.arguments.contains("--routes05-calendar-fixture-detail")
        debugDetailMode = ProcessInfo.processInfo.arguments.contains("--routes05-calendar-fixture-detail")
        let initialDate = debugFixtureMode ? ConceptCalendarDates.debugFixtureDate : referenceDate
        #else
        debugFixtureMode = false
        debugDetailMode = false
        let initialDate = referenceDate
        #endif
        _referenceDate = State(initialValue: initialDate)
        _visibleMonth = State(initialValue: ConceptCalendarDates.monthStart(initialDate))
        _weekAnchor = State(initialValue: initialDate)
    }

    private var activeEvents: [ConceptCalendarEvent] {
        events.filter { enabledSourceIDs.contains($0.sourceID) }
    }

    // The later queue remains independent of the displayed calendar and is
    // partitioned after the local next-week boundary.
    private var selectedDateSectionVisible: Bool {
        OrbitCalendarV2Logic.showsSelectedDateSection(selectedDate: selectedDate, today: referenceDate, calendar: calendar)
    }

    private var timeline: OrbitCalendarV2Logic.Timeline<ConceptCalendarEvent> {
        var excluded = Set<String>()
        if let selectedDate, selectedDateSectionVisible {
            excluded = Set(occurrences(on: selectedDate).map(OrbitCalendarV2Logic.eventKey))
        }
        return OrbitCalendarV2Logic.timeline(activeEvents, now: referenceDate, calendar: calendar, excluding: excluded, laterInterval: laterInterval)
    }

    private var nextFive: [ConceptCalendarEvent] { timeline.later }

    private var laterInterval: DateInterval {
        OrbitCalendarV2Logic.laterInterval(now: referenceDate, calendar: calendar)
            ?? DateInterval(start: afterNextWeekBoundary, end: afterNextWeekBoundary)
    }

    private var collapsedWeekAnchor: Date { selectedDate ?? weekAnchor }

    private var afterNextWeekBoundary: Date {
        guard let currentWeek = OrbitCalendarV2Logic.weekInterval(containing: referenceDate, calendar: calendar),
              let nextWeek = OrbitCalendarV2Logic.nextWeekInterval(after: currentWeek, calendar: calendar) else {
            return referenceDate
        }
        return nextWeek.end
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 17) {
                        Routes05Mast(section: "calendar", action: { showingSources = true }, backAction: onBack, backLabel: "Назад до Інше")
                        hero
                        ForEach(OrbitCalendarV2Logic.sectionOrder, id: \.self) { section in
                            timelineSection(section)
                        }
                        sourcesSummary
                        if let coverageText {
                            Text(coverageText)
                                .font(.caption)
                                .foregroundStyle(Routes05Tokens.secondary)
                                .padding(.horizontal, 16)
                        }
                        sourceNote
                        Color.clear.frame(height: 1).id("routes05-bottom")
                    }
                }
                .scrollIndicators(.hidden)
                .novaDockAwareScrollContent()
                #if DEBUG
                .onChange(of: isLoading) { _, loading in
                    guard !loading, Routes05DebugCapture.scrollToBottom else { return }
                    DispatchQueue.main.async { proxy.scrollTo("routes05-bottom", anchor: .bottom) }
                }
                #endif
            }
            .background(Routes05Tokens.canvas.ignoresSafeArea())
            .foregroundStyle(Routes05Tokens.ink)
            .toolbar(.hidden, for: .navigationBar)
            .environment(\.locale, Locale(identifier: "uk_UA"))
            .sheet(isPresented: $showingSources) { sourceManager }
            .sheet(isPresented: $showingCreator) {
                CalendarEventEditor(event: editingEvent) { _ in await load() }
            }
            .sheet(item: $selectedEvent) { event in eventDetail(event) }
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                referenceDate = .now
                weekAnchor = .now
                Task { await load() }
            }
            .alert("Помилка календаря", isPresented: Binding(
                get: { loadError != nil },
                set: { if !$0 { loadError = nil } }
            )) {
                Button("Гаразд") { loadError = nil }
            } message: {
                Text(loadError?.localizedDescription ?? "Спробуйте ще раз.")
            }
        }
    }

    // MARK: — Intro and today

    private var hero: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                eyebrow("FAMILY / SHARED TIME")
                Text("Календар.")
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                    .tracking(-1.5)
                    .accessibilityAddTraits(.isHeader)
                Text("Усі важливі події — в одному місці.")
                    .font(.footnote)
                    .foregroundStyle(Routes05Tokens.secondary)
            }
            Spacer(minLength: 4)
            Button(action: openCreator) {
                Image(systemName: "plus")
                    .font(.system(size: 25, weight: .black))
                    .foregroundStyle(Routes05Tokens.accentInk)
                    .frame(width: 58, height: 58)
                    .background(Routes05Tokens.yellow, in: Circle())
                    .overlay(Circle().stroke(Routes05Tokens.ink, lineWidth: 2))
            }
            .accessibilityLabel("Додати подію")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var sourcesSummary: some View {
        Button { showingSources = true } label: {
            HStack(spacing: 9) {
                HStack(spacing: 4) {
                    ForEach(sources.filter { enabledSourceIDs.contains($0.id) }) { source in
                        Circle().fill(source.color).frame(width: 9, height: 9)
                    }
                }
                Text("Календарі: \(enabledSourceIDs.count) із \(sources.count)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Керувати")
                    .font(.caption.weight(.bold))
                    .underline()
                Image(systemName: "slider.horizontal.3").font(.footnote)
            }
            .frame(minHeight: 46)
            .foregroundStyle(Routes05Tokens.ink)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .accessibilityLabel("Керування календарями. Активних \(enabledSourceIDs.count) із \(sources.count)")
    }

    // MARK: — Current week, expandable to a complete month

    private var monthCard: some View {
        VStack(alignment: .leading, spacing: displayMode == .week ? 4 : 11) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    if displayMode == .month { eyebrow("MONTH / OVERVIEW") }
                    Text(displayMode == .month ? ConceptCalendarDates.monthYear(visibleMonth) : ConceptCalendarDates.compactWeekRange(collapsedWeekAnchor))
                        .font(.system(displayMode == .month ? .title2 : .subheadline, design: .rounded, weight: .black))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer()
                monthArrow("chevron.left", shift: -1, label: displayMode == .month ? "Попередній місяць" : "Попередній тиждень")
                monthArrow("chevron.right", shift: 1, label: displayMode == .month ? "Наступний місяць" : "Наступний тиждень")
            }
            HStack(spacing: 0) {
                ForEach(["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "НД"], id: \.self) { label in
                    Text(label)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Routes05Tokens.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 3), count: 7), spacing: 4) {
                ForEach(displayMode == .month ? ConceptCalendarDates.monthGrid(visibleMonth) : OrbitCalendarV2Logic.weekDays(containing: collapsedWeekAnchor, calendar: calendar), id: \.self) { day in
                    dayButton(day)
                }
            }
            Button {
                if displayMode == .week {
                    visibleMonth = ConceptCalendarDates.monthStart(collapsedWeekAnchor)
                }
                displayMode.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text(displayMode == .month ? "Показати тиждень" : "Показати повний місяць")
                    Image(systemName: displayMode == .month ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                }
                .font(.caption.weight(.bold))
                .frame(minHeight: 44)
                .foregroundStyle(Routes05Tokens.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(displayMode == .month ? "Згорнути до тижня" : "Розгорнути до повного місяця")
            .accessibilityValue(displayMode == .month ? "Повний місяць" : "Поточний тиждень")
            HStack(spacing: 7) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Routes05Tokens.yellow)
                Text("Жовтий — сьогодні")
                Spacer()
                Text("Крапки — події календарів")
            }
            .font(.system(size: 10))
            .foregroundStyle(Routes05Tokens.secondary)
            if isLoading {
                ProgressView("Завантаження календаря…")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(displayMode == .month ? 13 : 8)
        .background(Routes05Tokens.surface)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Routes05Tokens.rule, lineWidth: 1.3))
        .padding(.horizontal, 16)
    }

    private func monthArrow(_ symbol: String, shift: Int, label: String) -> some View {
        Button {
            if displayMode == .month {
                guard let month = calendar.date(byAdding: .month, value: shift, to: visibleMonth) else { return }
                let anchor = calendar.date(byAdding: .month, value: shift, to: selectedDate ?? weekAnchor) ?? month
                visibleMonth = ConceptCalendarDates.monthStart(month)
                weekAnchor = anchor
            } else {
                guard let week = calendar.date(byAdding: .weekOfYear, value: shift, to: weekAnchor) else { return }
                weekAnchor = week
                visibleMonth = ConceptCalendarDates.monthStart(week)
            }
            selectedDate = nil
            let monthToLoad = visibleMonth
            Task { await loadMonth(monthToLoad) }
        } label: {
            Image(systemName: symbol)
                .font(.subheadline.weight(.black))
                .frame(width: 44, height: 44)
                .foregroundStyle(Routes05Tokens.ink)
                .background(Routes05Tokens.canvas)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Routes05Tokens.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func dayButton(_ day: Date) -> some View {
        let isToday = calendar.isDate(day, inSameDayAs: referenceDate)
        let isSelected = selectedDate.map { calendar.isDate(day, inSameDayAs: $0) } ?? false
        let inMonth = calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month)
        let dayEvents = occurrences(on: day)
        let colors = Array(Set(dayEvents.map(\.sourceID))).sorted().compactMap { id in sources.first(where: { $0.id == id })?.color }

        return Button {
            selectedDate = calendar.startOfDay(for: day)
            weekAnchor = day
            if !inMonth { visibleMonth = ConceptCalendarDates.monthStart(day) }
            if selectedDateSectionVisible && timeline.later.count < 5 {
                Task { await refreshTimelineCoverage() }
            }
        } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 15, weight: isToday || isSelected ? .black : .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                HStack(spacing: 2) {
                    ForEach(0..<min(3, colors.count), id: \.self) { index in
                        Circle()
                            .fill(colors[index])
                            .frame(width: 5, height: 5)
                            .overlay(Circle().stroke(isToday ? Routes05Tokens.accentInk : Routes05Tokens.surface, lineWidth: 0.25))
                    }
                }
                .frame(height: 7)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(isToday ? Routes05Tokens.accentInk : (inMonth ? Routes05Tokens.ink : Routes05Tokens.secondary.opacity(0.52)))
            .background(isToday ? Routes05Tokens.yellow : (isSelected ? Routes05Tokens.mint.opacity(0.22) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(isSelected ? Routes05Tokens.ink : Color.clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(ConceptCalendarDates.accessible(day)), \(dayEvents.count) подій\(isToday ? ", сьогодні" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func timelineSection(_ section: OrbitCalendarV2Logic.Section) -> some View {
        switch section {
        case .calendar:
            monthCard
        case .selectedDate:
            if selectedDateSectionVisible, let selectedDate {
                selectedDaySection(selectedDate)
            }
        case .today:
            todaySection
        case .thisWeek:
            eventsSection(
                eyebrow: "THIS WEEK / CURRENT",
                title: "Цей тиждень",
                events: timeline.thisWeek,
                emptyMessage: "На цей тиждень подій немає."
            )
        case .nextWeek:
            eventsSection(
                eyebrow: "NEXT WEEK",
                title: "Наступний тиждень",
                events: timeline.nextWeek,
                emptyMessage: "На наступний тиждень подій немає."
            )
        case .later:
            nextFiveSection
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "sun.max.fill").font(.caption).accessibilityHidden(true)
                Text("СЬОГОДНІ · \(ConceptCalendarDates.weekdayLong(referenceDate).capitalized)")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button("Сьогодні") { jumpToToday() }
                    .font(.caption.weight(.bold))
                    .frame(minHeight: 44)
                    .accessibilityLabel("Повернути календар до сьогодні")
            }
            if timeline.today.isEmpty {
                Text("На сьогодні подій немає.")
                    .font(.subheadline)
                    .foregroundStyle(Routes05Tokens.accentInk)
                    .padding(.vertical, 5)
            } else {
                ForEach(timeline.today, id: \.identityKey) { event in
                    upcomingRow(event, inTodaySection: true)
                }
            }
        }
        .padding(10)
        .background(Routes05Tokens.yellow.opacity(colorScheme == .dark ? 0.25 : 0.55))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Routes05Tokens.yellow, lineWidth: 1.5))
        .padding(.horizontal, 16)
        .foregroundStyle(Routes05Tokens.accentInk)
    }

    private func eventsSection(eyebrow label: String, title: String, events: [ConceptCalendarEvent], emptyMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                eyebrow(label)
                Text(title)
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, 16)
            eventRows(events, emptyMessage: emptyMessage)
        }
    }

    @ViewBuilder
    private func eventRows(_ events: [ConceptCalendarEvent], emptyMessage: String) -> some View {
        if events.isEmpty {
            if !isLoading {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(Routes05Tokens.secondary)
                    .padding(.horizontal, 16)
            }
        } else {
            ForEach(events, id: \.identityKey) { event in
                upcomingRow(event)
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: — Day selection independent of Next Five

    private func selectedDaySection(_ day: Date) -> some View {
        let dayEvents = occurrences(on: day).sorted { $0.startsAt < $1.startsAt }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("ОБРАНИЙ ДЕНЬ")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                Spacer()
                Button("Закрити") { selectedDate = nil }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Routes05Tokens.ink)
                    .frame(minHeight: 44)
            }
            Text(ConceptCalendarDates.accessible(day))
                .font(.system(.title3, design: .rounded, weight: .bold))
            if dayEvents.isEmpty {
                Text("Цього дня немає подій у вибраних календарях.")
                    .font(.subheadline)
                    .foregroundStyle(Routes05Tokens.secondary)
            } else {
                ForEach(dayEvents, id: \.identityKey) { event in
                    compactDayRow(event)
                }
            }
        }
        .padding(14)
        .background(Routes05Tokens.mint.opacity(colorScheme == .dark ? 0.10 : 0.16))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Routes05Tokens.mint, lineWidth: 1.5))
        .padding(.horizontal, 16)
    }

    private func compactDayRow(_ event: ConceptCalendarEvent) -> some View {
        Button { selectedEvent = event } label: {
            HStack(alignment: .top, spacing: 9) {
                RoundedRectangle(cornerRadius: 2).fill(source(event).color).frame(width: 4, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title).font(.subheadline.weight(.bold))
                    Text("\(event.allDay ? "Увесь день" : ConceptCalendarDates.time(event.startsAt)) · \(source(event).name)")
                        .font(.caption)
                        .foregroundStyle(Routes05Tokens.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }
            .frame(minHeight: 44)
            .foregroundStyle(Routes05Tokens.ink)
        }
        .buttonStyle(.plain)
    }

    // MARK: — Five events after the next-week period

    private var nextFiveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    eyebrow("UPCOMING / ALL CALENDARS")
                    Text("Далі")
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer()
                Image(systemName: "arrow.down")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Routes05Tokens.blue)
            }
            Text("До п’яти найраніших подій у межах одного календарного місяця.")
                .font(.footnote)
                .foregroundStyle(Routes05Tokens.secondary)
            if nextFive.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "calendar.badge.checkmark").font(.title2)
                    Text(coverageComplete ? "Майбутніх подій немає" : "Не вдалося підтвердити повний список")
                        .font(.headline)
                    Text(coverageComplete ? "Перевірте, які календарі увімкнені." : "Деякі календарі не повернули повні дані.")
                        .font(.subheadline)
                        .foregroundStyle(Routes05Tokens.secondary)
                    Button("Показати календарі") { showingSources = true }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Routes05Tokens.surface)
            } else {
                ForEach(nextFive, id: \.identityKey) { event in
                    upcomingRow(event)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func upcomingRow(_ event: ConceptCalendarEvent, inTodaySection: Bool = false) -> some View {
        let origin = source(event)
        let involved = names(for: event.involvedPersonIDs)
        let associated = names(for: origin.relatedPersonIDs)

        return Button { selectedEvent = event } label: {
            HStack(alignment: .top, spacing: 11) {
                RoundedRectangle(cornerRadius: 2).fill(origin.color).frame(width: 4, height: 40)
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Text(ConceptCalendarDates.relativeDate(event.startsAt, now: referenceDate))
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(Routes05Tokens.secondary)
                        Spacer(minLength: 0)
                        Text(event.allDay ? "Увесь день" : ConceptCalendarDates.time(event.startsAt))
                            .font(.system(.caption, design: .rounded, weight: .bold))
                    }
                    Text(event.title)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 5) {
                        Circle().fill(origin.color).frame(width: 7, height: 7)
                        Text(origin.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                    }
                    Text("Власник календаря: \(associated.isEmpty ? "Не надано сервером" : associated.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(Routes05Tokens.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("Учасники / запрошені:")
                            .font(.caption.weight(.semibold))
                        Text(involved.isEmpty ? "Не вказано" : involved.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(Routes05Tokens.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Routes05Tokens.secondary)
                    .padding(.top, 7)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(inTodaySection ? Routes05Tokens.yellow.opacity(colorScheme == .dark ? 0.18 : 0.30) : Routes05Tokens.surface)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Routes05Tokens.rule, lineWidth: 1))
            .foregroundStyle(Routes05Tokens.ink)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(ConceptCalendarDates.accessible(event.startsAt)). \(event.title). Календар \(origin.name). Пов’язаний із \(associated.joined(separator: ", ")). Залучені \(involved.isEmpty ? "не вказано" : involved.joined(separator: ", "))")
    }

    private var sourceNote: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle").font(.subheadline)
            Text("Власники календаря та учасники події — різні ролі. Orbit не призначатиме учасників автоматично лише за назвою iCloud-календаря.")
                .font(.footnote)
        }
        .foregroundStyle(Routes05Tokens.secondary)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: — Source selection

    private var sourceManager: some View {
        NavigationStack {
            List {
                Section {
                    Text("Виберіть, які календарі відображаються. Фільтр змінює календар і блок «Далі».")
                        .font(.footnote)
                }
                ForEach(sources) { source in
                    Toggle(isOn: Binding(
                        get: { enabledSourceIDs.contains(source.id) },
                        set: { enabled in
                            setSourceEnabled(source.id, enabled)
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Circle().fill(source.color).frame(width: 12, height: 12)
                                Text(source.name).font(.headline)
                            }
                            Text(source.accountLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Прив’язка до сімейних профілів не надана сервером")
                                .font(.caption)
                            if !source.writable {
                                Label("Лише перегляд", systemImage: "eye")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Календарі")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Усі") { enabledSourceIDs = Set(sources.map(\.id)) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { showingSources = false }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: — Live event creation/editing

    private func openCreator() {
        editingEvent = nil
        showingCreator = true
    }

    private func setSourceEnabled(_ id: String, _ enabled: Bool) {
        if enabled { enabledSourceIDs.insert(id) }
        else { enabledSourceIDs.remove(id) }
        guard sources.contains(where: { $0.id == id }) else { return }
        Task {
            do {
                _ = try await MainProductAPI.shared.updateCalendarSource(id: id, selected: enabled)
                await load()
            }
            catch { loadError = error }
        }
    }

    private func eventDetail(_ event: ConceptCalendarEvent) -> some View {
        let live = liveEvents.first {
            if let occurrenceId = event.occurrenceId { return $0.occurrenceId == occurrenceId }
            return $0.id == event.id && ($0.sourceIdentifier ?? $0.sourceType) == event.sourceID
        }
        return NavigationStack {
            List {
                Section("Подія") {
                    Text(event.title).font(.title3.weight(.bold))
                    LabeledContent("Дата", value: ConceptCalendarDates.accessible(event.startsAt))
                    LabeledContent("Час", value: event.allDay ? "Увесь день" : ConceptCalendarDates.time(event.startsAt))
                    LabeledContent("Календар", value: source(event).name)
                    LabeledContent("Акаунт", value: source(event).accountLabel)
                    LabeledContent("Власник календаря", value: "Не надано сервером")
                    LabeledContent("Власник / організатор", value: live.flatMap { names(for: [$0.ownerPersonId]).first } ?? "Не вказано")
                    LabeledContent("Учасники / запрошені", value: "Не вказано — API не повертає ці дані")
                    LabeledContent("Доступ", value: source(event).writable ? "Редагування дозволене" : "Лише перегляд")
                }
                if !event.notes.isEmpty {
                    Section("Примітка") { Text(event.notes) }
                }
            }
            .navigationTitle("Деталі")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Готово") { selectedEvent = nil } }
                if let live, live.sourceType == "orbit_family" {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Редагувати") { editingEvent = live; selectedEvent = nil; showingCreator = true }
                    }
                }
            }
        }
    }

    // MARK: — Live data

    private func load() async {
        isLoading = true
        #if DEBUG
        if debugFixtureMode {
            let fixture = ConceptCalendarDates.debugFixture(referenceDate: referenceDate)
            sources = fixture.sources
            enabledSourceIDs = Set(fixture.sources.map(\.id))
            events = fixture.events
            liveEvents = []
            people = fixture.people
            coverageText = "DEBUG fixture · synthetic data · API не викликався"
            coverageComplete = true
            loadError = nil
            isLoading = false
            if debugDetailMode {
                selectedEvent = fixture.events.first(where: { $0.id == "fixture-detail" })
            }
            return
        }
        #endif
        do {
            async let sourceResult = MainProductAPI.shared.calendarSources()
            async let monthResult = loadVisibleMonthEvents()
            let currentWeekStart = OrbitCalendarV2Logic.weekInterval(containing: referenceDate, calendar: calendar)?.start ?? calendar.startOfDay(for: referenceDate)
            async let weekResult = MainProductAPI.shared.calendarEvents(from: currentWeekStart, to: afterNextWeekBoundary, classifyUnavailable: true)
            let (apiSources, monthEvents, weekEvents) = try await (sourceResult, monthResult, weekResult)
            let selectedKeys: Set<String>
            if let selectedDate, selectedDateSectionVisible {
                selectedKeys = Set(occurrences(on: selectedDate).map(OrbitCalendarV2Logic.eventKey))
            } else {
                selectedKeys = []
            }
            let interval = laterInterval
            let upcoming = try await MainProductAPI.shared.laterCalendarEvents(
                from: interval.start,
                to: interval.end,
                timeZone: calendar.timeZone,
                excludingEventKeys: selectedKeys
            )
            let profiles = (try? await MainProductAPI.shared.familyProfiles()) ?? []

            people = profiles.map { ConceptCalendarPerson(id: $0.personId, name: $0.displayName) }
            let mappedSources = apiSources.map(ConceptCalendarSource.init)
            // Later-mode rows carry recurrence identity and local all-day dates;
            // keep those richer values when the same occurrence is also in a legacy window.
            let allAPIEvents = deduplicated(upcoming.events + monthEvents + weekEvents)
            let missingSources = allAPIEvents.compactMap { event -> ConceptCalendarSource? in
                let sourceID = event.sourceIdentifier ?? event.sourceType
                guard !mappedSources.contains(where: { $0.id == sourceID }) else { return nil }
                return ConceptCalendarSource(event: event)
            }
            sources = deduplicatedSources(mappedSources + missingSources)
            enabledSourceIDs = Set(apiSources.filter(\.selected).map(\.id))
            enabledSourceIDs.formUnion(missingSources.map(\.id))
            events = allAPIEvents.map { ConceptCalendarEvent(apiEvent: $0) }
            liveEvents = allAPIEvents
            coverageText = upcoming.coverageDescription
            coverageComplete = upcoming.complete
            loadError = nil
        } catch {
            loadError = error
        }
        isLoading = false
    }

    private func refreshTimelineCoverage() async {
        let selectedKeys: Set<String>
        if let selectedDate, selectedDateSectionVisible {
            selectedKeys = Set(occurrences(on: selectedDate).map(OrbitCalendarV2Logic.eventKey))
        } else {
            selectedKeys = []
        }
        do {
            let interval = laterInterval
            let upcoming = try await MainProductAPI.shared.laterCalendarEvents(
                from: interval.start,
                to: interval.end,
                timeZone: calendar.timeZone,
                excludingEventKeys: selectedKeys
            )
            let combined = deduplicated(upcoming.events + liveEvents)
            liveEvents = combined
            events = combined.map { ConceptCalendarEvent(apiEvent: $0) }
            coverageText = upcoming.coverageDescription
            coverageComplete = upcoming.complete
        } catch {
            loadError = error
        }
    }

    private func loadVisibleMonthEvents() async throws -> [OrbitCalendarEvent] {
        let month = ConceptCalendarDates.monthStart(visibleMonth)
        let first = ConceptCalendarDates.monthGrid(month).first ?? month
        let last = ConceptCalendarDates.monthGrid(month).last ?? month
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) ?? last
        return try await MainProductAPI.shared.calendarEvents(from: first, to: end, classifyUnavailable: true)
    }

    private func loadMonth(_ month: Date) async {
        do {
            let loaded = try await MainProductAPI.shared.calendarEvents(
                from: ConceptCalendarDates.monthGrid(month).first ?? month,
                to: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: ConceptCalendarDates.monthGrid(month).last ?? month)) ?? month,
                classifyUnavailable: true
            )
            let currentWeekStart = OrbitCalendarV2Logic.weekInterval(containing: referenceDate, calendar: calendar)?.start ?? calendar.startOfDay(for: referenceDate)
            let merged = deduplicated(liveEvents.filter { $0.startsAt >= currentWeekStart || $0.endsAt > referenceDate } + loaded)
            liveEvents = merged
            events = merged.map { ConceptCalendarEvent(apiEvent: $0) }
            loadError = nil
        } catch {
            loadError = error
        }
    }

    private func deduplicated(_ values: [OrbitCalendarEvent]) -> [OrbitCalendarEvent] {
        var seen = Set<String>()
        return values.filter { event in
            let source = event.sourceIdentifier ?? event.sourceType
            let key = event.occurrenceId ?? "\(source):\(event.id)"
            guard seen.insert(key).inserted else { return false }
            return true
        }
    }

    private func deduplicatedSources(_ values: [ConceptCalendarSource]) -> [ConceptCalendarSource] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }
    }

    // MARK: — Common helpers

    private func occurrences(on date: Date) -> [ConceptCalendarEvent] {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return activeEvents.filter { $0.startsAt < end && $0.endsAt > start }
    }

    private func source(_ event: ConceptCalendarEvent) -> ConceptCalendarSource {
        sources.first(where: { $0.id == event.sourceID }) ?? sources[0]
    }

    private func names(for ids: [String]) -> [String] {
        ids.compactMap { id in people.first(where: { $0.id == id })?.name }
    }

    private func jumpToToday() {
        visibleMonth = ConceptCalendarDates.monthStart(referenceDate)
        selectedDate = calendar.startOfDay(for: referenceDate)
        weekAnchor = referenceDate
        Task { await loadMonth(visibleMonth) }
    }

    private func eyebrow(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(Routes05Tokens.secondary)
    }
}

// MARK: — Presentation adapters. Participant links remain separate from
// source-person associations and are empty when the API does not provide them.

private struct ConceptCalendarPerson: Identifiable {
    let id: String
    let name: String
}

private struct ConceptCalendarSource: Identifiable {
    let id: String
    let name: String
    let accountLabel: String
    let color: Color
    let relatedPersonIDs: [String]
    let writable: Bool

    init(id: String, name: String, accountLabel: String, color: Color, relatedPersonIDs: [String], writable: Bool) {
        self.id = id
        self.name = name
        self.accountLabel = accountLabel
        self.color = color
        self.relatedPersonIDs = relatedPersonIDs
        self.writable = writable
    }

    init(_ source: OrbitCalendarSource) {
        id = source.id
        name = source.displayName
        accountLabel = "Підключення \(source.connectionId)"
        color = Color(calendarHex: source.color) ?? Routes05Tokens.blue
        relatedPersonIDs = []
        writable = source.writable
    }

    init(event: OrbitCalendarEvent) {
        id = event.sourceIdentifier ?? event.sourceType
        name = event.sourceName ?? (event.sourceType == "orbit_family" ? "Сімейний Orbit" : "Зовнішній календар")
        accountLabel = event.sourceType == "orbit_family" ? "Orbit · сімейний" : "Зовнішнє підключення"
        color = Color(calendarHex: event.sourceColor) ?? (event.sourceType == "orbit_family" ? Routes05Tokens.mint : Routes05Tokens.blue)
        relatedPersonIDs = []
        writable = event.sourceType == "orbit_family"
    }
}

private struct ConceptCalendarEvent: Identifiable, OrbitCalendarV2EventLike {
    let id: String
    let title: String
    let startsAt: Date
    let endsAt: Date
    let allDay: Bool
    let sourceID: String
    let involvedPersonIDs: [String]
    let notes: String
    let occurrenceId: String?

    var sourceType: String { sourceID }
    var sourceIdentifier: String? { nil }
    var identityKey: String { OrbitCalendarV2Logic.eventKey(self) }

    init(id: String, title: String, startsAt: Date, endsAt: Date, allDay: Bool, sourceID: String, involvedPersonIDs: [String], notes: String) {
        self.id = id
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.allDay = allDay
        self.sourceID = sourceID
        self.involvedPersonIDs = involvedPersonIDs
        self.notes = notes
        self.occurrenceId = nil
    }

    init(apiEvent: OrbitCalendarEvent) {
        id = apiEvent.id
        title = apiEvent.title
        startsAt = apiEvent.startsAt
        endsAt = apiEvent.endsAt
        allDay = apiEvent.allDay
        sourceID = apiEvent.sourceIdentifier ?? apiEvent.sourceType
        involvedPersonIDs = []
        notes = apiEvent.notes
        occurrenceId = apiEvent.occurrenceId
    }
}

private enum ConceptCalendarDates {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday
        c.locale = Locale(identifier: "uk_UA")
        c.timeZone = .current
        return c
    }

    static func monthStart(_ date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func monthGrid(_ date: Date) -> [Date] {
        let month = monthStart(date)
        let weekday = calendar.component(.weekday, from: month)
        let leading = (weekday + 5) % 7 // Monday -> 0, Sunday -> 6
        let first = calendar.date(byAdding: .day, value: -leading, to: month) ?? month
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "uk_UA")
        f.dateFormat = pattern
        return f
    }

    static func monthYear(_ date: Date) -> String { formatter("LLLL yyyy").string(from: date).capitalized }
    static func shortMonth(_ date: Date) -> String { formatter("LLL").string(from: date) }
    static func weekdayLong(_ date: Date) -> String { formatter("EEEE").string(from: date) }
    static func compactWeekRange(_ date: Date) -> String {
        guard let interval = OrbitCalendarV2Logic.weekInterval(containing: date, calendar: calendar),
              let last = calendar.date(byAdding: .day, value: -1, to: interval.end) else { return monthYear(date) }
        let sameMonth = calendar.component(.month, from: interval.start) == calendar.component(.month, from: last)
        let sameYear = calendar.component(.year, from: interval.start) == calendar.component(.year, from: last)
        let firstFormatter = formatter(sameYear && sameMonth ? "d" : (sameYear ? "d MMM" : "d MMM yyyy"))
        let lastFormatter = formatter(sameYear ? "d MMM" : "d MMM yyyy")
        return "\(firstFormatter.string(from: interval.start))–\(lastFormatter.string(from: last))"
    }
    static func weekRange(_ date: Date) -> String {
        guard let interval = OrbitCalendarV2Logic.weekInterval(containing: date, calendar: calendar),
              let last = calendar.date(byAdding: .day, value: -1, to: interval.end) else { return monthYear(date) }
        let sameYear = calendar.component(.year, from: interval.start) == calendar.component(.year, from: last)
        let firstFormatter = formatter(sameYear ? "d MMM" : "d MMM yyyy")
        return "\(firstFormatter.string(from: interval.start)) – \(formatter("d MMM yyyy").string(from: last))"
    }
    static func accessible(_ date: Date) -> String { formatter("EEEE, d MMMM yyyy").string(from: date) }
    static func time(_ date: Date) -> String { formatter("HH:mm").string(from: date) }

    static func relativeDate(_ date: Date, now: Date) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "СЬОГОДНІ · \(formatter("d LLL").string(from: date))" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "ЗАВТРА · \(formatter("d LLL").string(from: date))"
        }
        return formatter("EEE · d LLL yyyy").string(from: date).uppercased()
    }

    #if DEBUG
    static var debugFixtureDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 9))!
    }

    static func debugFixture(referenceDate: Date) -> (sources: [ConceptCalendarSource], events: [ConceptCalendarEvent], people: [ConceptCalendarPerson]) {
        let day = calendar.startOfDay(for: referenceDate)
        func date(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(byAdding: .minute, value: hour * 60 + minute, to: calendar.date(byAdding: .day, value: offset, to: day)!)!
        }
        let sources = [
            ConceptCalendarSource(id: "fixture-family", name: "Сімейний Orbit", accountLabel: "DEBUG · family", color: Routes05Tokens.mint, relatedPersonIDs: [], writable: true),
            ConceptCalendarSource(id: "fixture-icloud", name: "iCloud · Спільний", accountLabel: "DEBUG · iCloud", color: Routes05Tokens.blue, relatedPersonIDs: [], writable: false),
            ConceptCalendarSource(id: "fixture-school", name: "Школа", accountLabel: "DEBUG · external", color: Routes05Tokens.orange, relatedPersonIDs: [], writable: false)
        ]
        let events = [
            ConceptCalendarEvent(id: "fixture-today", title: "Сьогодні · сімейний обід", startsAt: date(0, 12), endsAt: date(0, 13), allDay: false, sourceID: "fixture-family", involvedPersonIDs: [], notes: "Synthetic fixture"),
            ConceptCalendarEvent(id: "fixture-detail", title: "Сімейна вечеря", startsAt: date(1, 18, 30), endsAt: date(1, 20), allDay: false, sourceID: "fixture-family", involvedPersonIDs: [], notes: "Місце: кухня"),
            ConceptCalendarEvent(id: "fixture-all-day", title: "Осінні канікули", startsAt: date(3, 0), endsAt: date(6, 0), allDay: true, sourceID: "fixture-icloud", involvedPersonIDs: [], notes: "Multi-day fixture"),
            ConceptCalendarEvent(id: "fixture-overlap", title: "Плавання", startsAt: date(4, 17), endsAt: date(4, 18), allDay: false, sourceID: "fixture-school", involvedPersonIDs: [], notes: "Overlapping source"),
            ConceptCalendarEvent(id: "fixture-future-1", title: "Планування тижня", startsAt: date(8, 9), endsAt: date(8, 10), allDay: false, sourceID: "fixture-family", involvedPersonIDs: [], notes: "Upcoming fixture"),
            ConceptCalendarEvent(id: "fixture-future-2", title: "Візит до лікаря", startsAt: date(15, 14), endsAt: date(15, 15), allDay: false, sourceID: "fixture-icloud", involvedPersonIDs: [], notes: "Upcoming fixture"),
            ConceptCalendarEvent(id: "fixture-future-3", title: "День народження", startsAt: date(31, 11), endsAt: date(31, 12), allDay: false, sourceID: "fixture-family", involvedPersonIDs: [], notes: "Upcoming fixture"),
            ConceptCalendarEvent(id: "fixture-future-4", title: "Подія наступного місяця", startsAt: date(39, 16), endsAt: date(39, 17), allDay: false, sourceID: "fixture-school", involvedPersonIDs: [], notes: "Upcoming fixture"),
            ConceptCalendarEvent(id: "fixture-future-5", title: "Подія через два місяці", startsAt: date(68, 10), endsAt: date(68, 11), allDay: false, sourceID: "fixture-icloud", involvedPersonIDs: [], notes: "Upcoming fixture"),
            ConceptCalendarEvent(id: "fixture-future-6", title: "Подія за кілька місяців", startsAt: date(95, 10), endsAt: date(95, 11), allDay: false, sourceID: "fixture-family", involvedPersonIDs: [], notes: "Upcoming fixture")
        ]
        return (sources, events, [])
    }
    #endif
}

#Preview("Calendar · light") {
    OrbitCalendarV2View()
        .preferredColorScheme(.light)
}

#Preview("Calendar · dark") {
    OrbitCalendarV2View()
        .preferredColorScheme(.dark)
}

private extension Color {
    init?(calendarHex value: String?) {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard normalized.count == 6, let rgb = UInt64(normalized, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xff) / 255,
                  green: Double((rgb >> 8) & 0xff) / 255,
                  blue: Double(rgb & 0xff) / 255,
                  opacity: 1)
    }
}
