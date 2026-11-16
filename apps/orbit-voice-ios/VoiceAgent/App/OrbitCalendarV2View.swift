import SwiftUI

/// Stable navigation owner. The authored ROUTES 05 concept is implemented by
/// the live view below so existing Main Orbit navigation keeps its contract.
struct OrbitCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    var origin: OrbitCalendarRouteOrigin = .root

    var body: some View {
        OrbitCalendarV2View(onBack: origin.showsBackControl ? { dismiss() } : nil)
            // The calendar hosts its own NavigationStack and draws its own Back; hide the
            // outer bar when pushed so exactly one Back control remains.
            .toolbar(origin.showsBackControl ? .hidden : .automatic, for: .navigationBar)
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
    @State private var providerEditing: OrbitCalendarEvent?
    @State private var selectedEvent: ConceptCalendarEvent?
    @State private var editingEvent: OrbitCalendarEvent?

    @ScaledMetric(relativeTo: .caption) private var agendaTimeColumnWidth: CGFloat = 54
    @State private var agendaScrollDate: Date?
    @State private var agendaScrollRequest: Date?
    @State private var agendaScrollRequestToken = UUID()
    @State private var agendaScrollLocked = false
    @State private var agendaScrollUnlockTask: Task<Void, Never>?
    @State private var agendaNavigationTask: Task<Void, Never>?
    @State private var agendaNavigationGeneration = 0
    @State private var agendaLoadingRange = false
    @State private var hasLoadedAgendaData = false
    @State private var agendaLoadFailed = false
    @State private var coverageLoadFailed = false

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
        let selectedDate = ProcessInfo.processInfo.arguments.contains("--routes05-calendar-select-tomorrow")
            ? (ConceptCalendarDates.calendar.date(byAdding: .day, value: 1, to: initialDate) ?? initialDate)
            : initialDate
        _displayMode = State(initialValue: ProcessInfo.processInfo.arguments.contains("--routes05-calendar-month-expanded") ? .month : .week)
        #else
        debugFixtureMode = false
        debugDetailMode = false
        let initialDate = referenceDate
        let selectedDate = initialDate
        _displayMode = State(initialValue: .week)
        #endif
        _referenceDate = State(initialValue: initialDate)
        _visibleMonth = State(initialValue: ConceptCalendarDates.monthStart(selectedDate))
        _weekAnchor = State(initialValue: selectedDate)
        _selectedDate = State(initialValue: ConceptCalendarDates.calendar.startOfDay(for: selectedDate))
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

    private var collapsedWeekAnchor: Date { weekAnchor }

    private var agendaSelectedDay: Date {
        calendar.startOfDay(for: selectedDate ?? weekAnchor)
    }

    private var agendaWeekDays: [Date] {
        OrbitCalendarV2Logic.weekDays(containing: weekAnchor, calendar: calendar)
            .map { calendar.startOfDay(for: $0) }
    }

    private func agendaEvents(on day: Date) -> [ConceptCalendarEvent] {
        OrbitCalendarV2Logic.orderedAgendaEvents(occurrences(on: day))
    }

    private func agendaDayTitle(_ day: Date) -> String {
        if calendar.isDate(day, inSameDayAs: referenceDate) { return "Сьогодні" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: referenceDate)),
           calendar.isDate(day, inSameDayAs: tomorrow) { return "Завтра" }
        return ConceptCalendarDates.weekdayLong(day).capitalized
    }

    private func agendaDayCaption(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "uk_UA")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMM"
        return formatter.string(from: day)
    }

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
                agendaLayout(proxy: proxy)
            }
            .foregroundStyle(Routes05Tokens.ink)
            .toolbar(.hidden, for: .navigationBar)
            .routes05NativeSwipeBack()
            .environment(\.locale, Locale(identifier: "uk_UA"))
            .sheet(isPresented: $showingSources) { sourceManager }
            .sheet(isPresented: $showingCreator) {
                CalendarEventEditor(event: editingEvent, initialDate: selectedDate ?? weekAnchor) { _ in await load() }
            }
            .sheet(item: $selectedEvent) { event in eventDetail(event) }
            .sheet(item: $providerEditing) { event in
                ProviderEventEditor(event: event) { await load() }
            }
            .task {
                await load()
                #if DEBUG
                if !Routes05DebugCapture.scrollToBottom { requestAgendaScroll(to: selectedDate ?? referenceDate) }
                #else
                requestAgendaScroll(to: selectedDate ?? referenceDate)
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                referenceDate = .now
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

    private func agendaLayout(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            Routes05Mast(section: "calendar", action: { showingSources = true }, backAction: onBack, backLabel: "Назад")
            hero
                .padding(.bottom, 4)

            HStack(spacing: 8) {
                Text(ConceptCalendarDates.monthYear(visibleMonth))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Routes05Tokens.ink)
                Spacer(minLength: 8)
                Button {
                    displayMode = .week
                    selectAgendaDay(referenceDate, loadRange: true)
                } label: {
                    Text("Сьогодні")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Routes05Tokens.rule, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Повернутися до сьогодні")
            }
            .padding(.horizontal, 16)

            monthCard
            agendaSourceBar
            Divider()
            agendaScrollContent(proxy: proxy)
        }
        .background(Routes05Tokens.canvas.ignoresSafeArea())
    }

    private func agendaScrollContent(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(agendaWeekDays, id: \.self) { day in
                    agendaDayGroup(day)
                        .id(day)
                }
                agendaUpcomingSection
                sourceNote
                Color.clear.frame(height: 1).id("routes05-bottom")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .scrollTargetLayout()
        }
        .scrollPosition(id: $agendaScrollDate, anchor: .top)
        .scrollIndicators(.hidden)
        .novaDockAwareScrollContent()
        .refreshable {
            await Task { await refreshMirrorThenLoad() }.value
        }
        .onChange(of: agendaScrollDate) { _, day in
            guard let day, !agendaScrollLocked, agendaWeekDays.contains(day) else { return }
            selectedDate = calendar.startOfDay(for: day)
        }
        .onChange(of: agendaScrollRequestToken) { _, token in
            guard let day = agendaScrollRequest else { return }
            agendaScrollLocked = true
            agendaScrollUnlockTask?.cancel()
            withAnimation(.easeInOut(duration: 0.22)) {
                proxy.scrollTo(day, anchor: .top)
            }
            agendaScrollUnlockTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled, agendaScrollRequestToken == token else { return }
                agendaScrollLocked = false
                agendaScrollRequest = nil
            }
        }
        #if DEBUG
        .onChange(of: isLoading) { _, loading in
            guard !loading, Routes05DebugCapture.scrollToBottom else { return }
            DispatchQueue.main.async { proxy.scrollTo("routes05-bottom", anchor: .bottom) }
        }
        #endif
    }

    // MARK: — Intro and today

    private var hero: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                eyebrow("FAMILY / SHARED TIME")
                Text("Календар.")
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .tracking(-1.2)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 4)
            Button(action: openCreator) {
                Image(systemName: "plus")
                    .font(.system(size: 25, weight: .black))
                    .foregroundStyle(Routes05Tokens.accentInk)
                    .frame(width: 46, height: 46)
                    .background(Routes05Tokens.yellow, in: Circle())
                    .overlay(Circle().stroke(Routes05Tokens.ink, lineWidth: 2))
            }
            .accessibilityLabel("Додати подію")
            .orbitRequires(.calendarProviderWrite)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var agendaSourceBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(sources.filter { enabledSourceIDs.contains($0.id) }) { source in
                    Circle().fill(source.color).frame(width: 7, height: 7)
                }
            }
            Text("Календарі: \(enabledSourceIDs.count) із \(sources.count)")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button { showingSources = true } label: {
                Label("Фільтри", systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.bold))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Routes05Tokens.ink)
        .padding(.horizontal, 16)
    }

    // MARK: — Current week, expandable to a complete month

    private var monthCard: some View {
        VStack(alignment: .leading, spacing: displayMode == .week ? 2 : 9) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayMode == .month ? ConceptCalendarDates.monthYear(visibleMonth) : ConceptCalendarDates.compactWeekRange(collapsedWeekAnchor))
                        .font(.system(displayMode == .month ? .subheadline : .caption, design: .rounded, weight: .black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer()
                monthArrow("chevron.left", shift: -1, label: displayMode == .month ? "Попередній місяць" : "Попередній тиждень")
                monthArrow("chevron.right", shift: 1, label: displayMode == .month ? "Наступний місяць" : "Наступний тиждень")
                Button(action: toggleMonthDisplay) {
                    Image(systemName: displayMode == .week ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.bold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(Routes05Tokens.ink)
                        .background(Routes05Tokens.canvas)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Routes05Tokens.rule, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(displayMode == .week ? "Розгорнути календар на місяць" : "Згорнути календар до тижня")
            }
            if displayMode == .month {
                HStack(spacing: 0) {
                    ForEach(["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "НД"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Routes05Tokens.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 3), count: 7), spacing: 4) {
                ForEach(displayMode == .month ? ConceptCalendarDates.monthGrid(visibleMonth) : OrbitCalendarV2Logic.weekDays(containing: collapsedWeekAnchor, calendar: calendar), id: \.self) { day in
                    dayButton(day)
                }
            }
            .simultaneousGesture(dateGridSwipeGesture())
            if displayMode == .month {
                HStack(spacing: 7) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Routes05Tokens.yellow)
                    Text("Жовтий — обраний день")
                    Spacer()
                    Text("Контур — сьогодні · крапки — події")
                }
                .font(.system(size: 10))
                .foregroundStyle(Routes05Tokens.secondary)
            }
            if isLoading {
                ProgressView("Завантаження календаря…")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if agendaLoadingRange {
                ProgressView("Завантаження подій…")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(displayMode == .month ? 10 : 5)
        .background(Routes05Tokens.surface)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Routes05Tokens.rule, lineWidth: 1.3))
        .padding(.horizontal, 16)
    }

    private func toggleMonthDisplay() {
        if displayMode == .week {
            visibleMonth = ConceptCalendarDates.monthStart(agendaSelectedDay)
        }
        withAnimation(.easeInOut(duration: 0.2)) { displayMode.toggle() }
    }

    private func monthArrow(_ symbol: String, shift: Int, label: String) -> some View {
        Button {
            if displayMode == .month {
                guard let month = calendar.date(byAdding: .month, value: shift, to: visibleMonth) else { return }
                guard let day = OrbitCalendarV2Logic.dateClamped(toMonth: month, preservingDayFrom: agendaSelectedDay, calendar: calendar) else { return }
                selectAgendaDay(day, loadRange: true)
            } else {
                guard let week = calendar.date(byAdding: .weekOfYear, value: shift, to: agendaSelectedDay) else { return }
                selectAgendaDay(week, loadRange: true)
            }
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
            selectAgendaDay(day, loadRange: !inMonth)
        } label: {
            VStack(spacing: displayMode == .week ? 0 : 4) {
                if displayMode == .week {
                    Text(ConceptCalendarDates.weekdayInitial(day))
                        .font(.caption2.weight(.bold).monospaced())
                        .foregroundStyle(Routes05Tokens.secondary)
                }
                Text(day.formatted(.dateTime.day()))
                    .font(.system(.body, design: .rounded, weight: isToday || isSelected ? .black : .semibold))
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
            // Week strip: keep the weekday initial clear of the card's top edge
            // (the label sat ~2pt from the border) without shrinking other content.
            .padding(.top, displayMode == .week ? OrbitCalendarCardMetrics.weekdayTopInset : 0)
            .frame(maxWidth: .infinity, minHeight: displayMode == .week ? OrbitCalendarCardMetrics.weekCardMinHeight : 44)
            .foregroundStyle(isSelected ? Routes05Tokens.accentInk : (inMonth ? Routes05Tokens.ink : Routes05Tokens.secondary.opacity(0.52)))
            .background(isSelected ? Routes05Tokens.yellow : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(isToday ? Routes05Tokens.ink : Color.clear, lineWidth: 1.3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(ConceptCalendarDates.accessible(day)), \(dayEvents.count) подій\(isToday ? ", сьогодні" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func dateGridSwipeGesture() -> some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                let horizontal = value.translation.width
                guard value.startLocation.x > 28,
                      abs(horizontal) > 64,
                      abs(horizontal) > abs(value.translation.height) * 1.35 else { return }
                let shift = horizontal < 0 ? 1 : -1
                if displayMode == .month {
                    guard let month = calendar.date(byAdding: .month, value: shift, to: visibleMonth),
                          let date = OrbitCalendarV2Logic.dateClamped(toMonth: month, preservingDayFrom: agendaSelectedDay, calendar: calendar) else { return }
                    selectAgendaDay(date, loadRange: true)
                } else if let date = calendar.date(byAdding: .weekOfYear, value: shift, to: agendaSelectedDay) {
                    selectAgendaDay(date, loadRange: true)
                }
            }
    }

    private func agendaDayGroup(_ day: Date, events suppliedEvents: [ConceptCalendarEvent]? = nil) -> some View {
        let dayEvents = OrbitCalendarV2Logic.orderedAgendaEvents(suppliedEvents ?? agendaEvents(on: day))
        let isToday = calendar.isDate(day, inSameDayAs: referenceDate)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                if isToday {
                    Image(systemName: "sun.max.fill")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
                Text(agendaDayTitle(day))
                    .font(.system(.headline, design: .rounded, weight: .black))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(agendaDayCaption(day))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Routes05Tokens.secondary)
            }

            if dayEvents.isEmpty {
                Group {
                    if isLoading || agendaLoadingRange {
                        Text("Завантаження подій…")
                    } else if agendaLoadFailed || loadError != nil {
                        Text("Не вдалося завантажити події для цього дня.")
                    } else if hasLoadedAgendaData {
                        Text("Немає запланованих подій")
                    } else {
                        Text("Список подій ще не завантажено.")
                    }
                }
                .font(.caption)
                .foregroundStyle(Routes05Tokens.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Routes05Tokens.surface)
            } else {
                VStack(spacing: 0) {
                    ForEach(dayEvents, id: \.identityKey) { event in
                        agendaEventRow(event, on: day)
                    }
                }
                .background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Routes05Tokens.rule, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            }
        }
        .padding(10)
        .background(isToday ? Routes05Tokens.yellow.opacity(colorScheme == .dark ? 0.32 : 0.48) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isToday ? Routes05Tokens.yellow : Color.clear, lineWidth: 1.2))
    }

    private func agendaEventRow(_ event: ConceptCalendarEvent, on day: Date) -> some View {
        let origin = sources.first { $0.id == event.sourceID }
        let color = origin?.color ?? Routes05Tokens.blue
        let sourceName = origin?.name ?? "Календар"
        let dayStart = calendar.startOfDay(for: day)
        let timeText = event.allDay
            ? "Весь день"
            : (event.startsAt < dayStart ? "Триває" : ConceptCalendarDates.time(event.startsAt))

        return Button {
            selectedEvent = event
        } label: {
            HStack(alignment: .center, spacing: 9) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 4, height: 36)
                    .accessibilityHidden(true)
                Text(timeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Routes05Tokens.ink)
                    .frame(width: agendaTimeColumnWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Routes05Tokens.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 5) {
                        Circle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true)
                        Text(sourceName)
                            .font(.caption)
                            .foregroundStyle(Routes05Tokens.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !event.attendees.isEmpty {
                            Text("· \(event.attendees.count) учасн.")
                                .font(.caption2)
                                .foregroundStyle(Routes05Tokens.secondary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Routes05Tokens.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Відкрити деталі події")
    }

    private func agendaDays(for events: [ConceptCalendarEvent]) -> [Date] {
        var days = Set<Date>()
        for event in events {
            var day = calendar.startOfDay(for: event.startsAt)
            let lastInstant = event.endsAt > event.startsAt ? event.endsAt.addingTimeInterval(-1) : event.startsAt
            let lastDay = calendar.startOfDay(for: lastInstant)
            while day <= lastDay {
                days.insert(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
                day = next
            }
        }
        return days.sorted()
    }

    private func agendaGroups(for events: [ConceptCalendarEvent], days requestedDays: [Date]? = nil) -> some View {
        let days = requestedDays ?? agendaDays(for: events)
        return ForEach(days.filter { day in events.contains { OrbitCalendarV2Logic.occurs($0, on: day, calendar: calendar) } }, id: \.self) { day in
            agendaDayGroup(day, events: events.filter { OrbitCalendarV2Logic.occurs($0, on: day, calendar: calendar) })
        }
    }

    private var agendaUpcomingSection: some View {
        let visibleKeys = Set(agendaWeekDays.flatMap { agendaEvents(on: $0) }.map(OrbitCalendarV2Logic.eventKey))
        let nextWeekEvents = timeline.nextWeek.filter { !visibleKeys.contains(OrbitCalendarV2Logic.eventKey($0)) }
        let nextWeekKeys = Set(nextWeekEvents.map(OrbitCalendarV2Logic.eventKey))
        let nextWeekWasVisibleAbove = !timeline.nextWeek.isEmpty && nextWeekEvents.isEmpty
        let laterEvents = timeline.later.filter {
            let key = OrbitCalendarV2Logic.eventKey($0)
            return !visibleKeys.contains(key) && !nextWeekKeys.contains(key)
        }
        let laterWasVisibleAbove = !timeline.later.isEmpty && laterEvents.isEmpty
        let nextWeekStart = OrbitCalendarV2Logic.weekInterval(containing: referenceDate, calendar: calendar)?.end
        let nextWeekDays = nextWeekStart.map { start in
            (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        } ?? []

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("НАСТУПНИЙ ТИЖДЕНЬ")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(Routes05Tokens.secondary)
                if nextWeekWasVisibleAbove {
                    Text("Події наступного тижня показані вище.")
                        .font(.caption)
                        .foregroundStyle(Routes05Tokens.secondary)
                } else if nextWeekEvents.isEmpty {
                    Text("На наступний тиждень подій немає.")
                        .font(.caption)
                        .foregroundStyle(Routes05Tokens.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 9))
                } else {
                    agendaGroups(for: nextWeekEvents, days: nextWeekDays)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("UPCOMING / SELECTED CALENDARS")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .tracking(1.1)
                            .foregroundStyle(Routes05Tokens.secondary)
                        Text("Далі")
                            .font(.system(.title3, design: .rounded, weight: .black))
                            .accessibilityAddTraits(.isHeader)
                    }
                    Spacer()
                    Image(systemName: "arrow.down")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Routes05Tokens.blue)
                        .accessibilityHidden(true)
                }
                Text("До п’яти найраніших подій у межах одного календарного місяця.")
                    .font(.footnote)
                    .foregroundStyle(Routes05Tokens.secondary)
                if laterWasVisibleAbove {
                    Text("Події цього періоду показані вище.")
                        .font(.caption)
                        .foregroundStyle(Routes05Tokens.secondary)
                } else if laterEvents.isEmpty {
                    Text(coverageComplete ? "Майбутніх подій немає" : (coverageLoadFailed ? "Не вдалося підтвердити повний список" : "Список майбутніх подій ще завантажується"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Routes05Tokens.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 9))
                } else {
                    agendaGroups(for: laterEvents)
                }
                if let coverageText {
                    Text(coverageText)
                        .font(.caption)
                        .foregroundStyle(Routes05Tokens.secondary)
                }
            }
        }
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
                    LabeledContent("Власник календаря", value: ownerNames(event, origin: source(event)).isEmpty ? "Спільний календар" : ownerNames(event, origin: source(event)).joined(separator: ", "))
                    LabeledContent("Організатор", value: organizerText(live))
                    LabeledContent("Учасники / запрошені", value: attendeeLabels(event).isEmpty ? "Немає" : attendeeLabels(event).joined(separator: ", "))
                    if let place = live?.location, !place.isEmpty {
                        LabeledContent("Місце", value: place)
                    }
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
                if let live, live.mirrorEventId != nil, live.capabilities?.edit.isEmpty == false || live.capabilities?.delete == true {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Змінити") { providerEditing = live; selectedEvent = nil }
                    }
                }
            }
        }
    }

    // MARK: — Live data

    private func load() async {
        let navigationGeneration = agendaNavigationGeneration
        isLoading = true
        agendaLoadFailed = false
        coverageLoadFailed = false
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
            hasLoadedAgendaData = true
            agendaLoadFailed = false
            coverageLoadFailed = false
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
            let isLatestNavigation = navigationGeneration == agendaNavigationGeneration
            let committedEvents = isLatestNavigation
                ? allAPIEvents
                : deduplicated(liveEvents + allAPIEvents)
            liveEvents = committedEvents
            events = committedEvents.map { ConceptCalendarEvent(apiEvent: $0) }
            if isLatestNavigation {
                coverageText = upcoming.coverageDescription
                coverageComplete = upcoming.complete
                loadError = nil
                agendaLoadFailed = false
                coverageLoadFailed = false
            }
            hasLoadedAgendaData = true
        } catch {
            if navigationGeneration == agendaNavigationGeneration {
                loadError = error
                agendaLoadFailed = true
                coverageLoadFailed = true
            }
        }
        isLoading = false
    }

    private func refreshTimelineCoverage() async {
        let navigationGeneration = agendaNavigationGeneration
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
            guard navigationGeneration == agendaNavigationGeneration else { return }
            let combined = deduplicated(upcoming.events + liveEvents)
            liveEvents = combined
            events = combined.map { ConceptCalendarEvent(apiEvent: $0) }
            coverageText = upcoming.coverageDescription
            coverageComplete = upcoming.complete
            coverageLoadFailed = false
        } catch {
            guard navigationGeneration == agendaNavigationGeneration else { return }
            loadError = error
            coverageLoadFailed = true
        }
    }

    private func loadVisibleMonthEvents() async throws -> [OrbitCalendarEvent] {
        let month = ConceptCalendarDates.monthStart(visibleMonth)
        let first = ConceptCalendarDates.monthGrid(month).first ?? month
        let last = ConceptCalendarDates.monthGrid(month).last ?? month
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) ?? last
        return try await MainProductAPI.shared.calendarEvents(from: first, to: end, classifyUnavailable: true)
    }

    private func loadMonthEvents(_ month: Date) async throws -> [OrbitCalendarEvent] {
        let monthDates = ConceptCalendarDates.monthGrid(month)
        let first = monthDates.first ?? month
        let last = monthDates.last ?? month
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) ?? last
        return try await MainProductAPI.shared.calendarEvents(from: first, to: end, classifyUnavailable: true)
    }

    private func selectAgendaDay(_ date: Date, loadRange: Bool) {
        let day = calendar.startOfDay(for: date)
        let previousMonth = visibleMonth
        selectedDate = day
        weekAnchor = day
        visibleMonth = ConceptCalendarDates.monthStart(day)
        requestAgendaScroll(to: day)

        let monthChanged = !calendar.isDate(previousMonth, equalTo: visibleMonth, toGranularity: .month)
        agendaNavigationGeneration += 1
        let generation = agendaNavigationGeneration
        agendaNavigationTask?.cancel()
        agendaLoadingRange = false

        if loadRange || monthChanged {
            let month = visibleMonth
            agendaLoadingRange = true
            agendaNavigationTask = Task {
                do {
                    let loaded = try await loadMonthEvents(month)
                    guard !Task.isCancelled, generation == agendaNavigationGeneration else { return }
                    let currentWeekStart = OrbitCalendarV2Logic.weekInterval(containing: day, calendar: calendar)?.start ?? day
                    let retained = liveEvents.filter { $0.startsAt >= currentWeekStart || $0.endsAt > referenceDate }
                    let merged = deduplicated(loaded + retained)
                    liveEvents = merged
                    events = merged.map { ConceptCalendarEvent(apiEvent: $0) }
                    loadError = nil
                    agendaLoadFailed = false
                    hasLoadedAgendaData = true
                } catch {
                    guard !Task.isCancelled, generation == agendaNavigationGeneration else { return }
                    loadError = error
                    agendaLoadFailed = true
                }
                guard generation == agendaNavigationGeneration else { return }
                agendaLoadingRange = false
                if selectedDateSectionVisible && timeline.later.count < 5 {
                    await refreshTimelineCoverage()
                }
            }
        } else if selectedDateSectionVisible && timeline.later.count < 5 {
            Task { await refreshTimelineCoverage() }
        }
    }

    private func requestAgendaScroll(to day: Date) {
        agendaScrollRequest = calendar.startOfDay(for: day)
        agendaScrollRequestToken = UUID()
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
        if let source = sources.first(where: { $0.id == event.sourceID }) { return source }
        if let live = liveEvents.first(where: {
            $0.id == event.id && ($0.sourceIdentifier ?? $0.sourceType) == event.sourceID
        }) {
            return ConceptCalendarSource(event: live)
        }
        return ConceptCalendarSource(
            id: event.sourceID,
            name: "Календар",
            accountLabel: "",
            color: Routes05Tokens.blue,
            relatedPersonIDs: [],
            writable: false
        )
    }

    private func names(for ids: [String]) -> [String] {
        ids.compactMap { id in people.first(where: { $0.id == id })?.name }
    }

    /// Calendar owner(s): people linked to the calendar plus the owner the server reports for the event (e.g. Alex's own calendar).
    private func ownerNames(_ event: ConceptCalendarEvent, origin: ConceptCalendarSource) -> [String] {
        var ids = origin.relatedPersonIDs
        for id in event.calendarOwnerIDs where !ids.contains(id) { ids.append(id) }
        return names(for: ids)
    }

    private static func attendeeStatusText(_ status: String?) -> String {
        switch (status ?? "").uppercased() {
        case "ACCEPTED": return "прийняв(ла)"
        case "DECLINED": return "відхилив(ла)"
        case "TENTATIVE": return "можливо"
        case "NEEDS-ACTION": return "очікує відповіді"
        default: return ""
        }
    }

    /// Invited people with their reply status; family members by name, others by the display name the calendar provided.
    private func attendeeLabels(_ event: ConceptCalendarEvent) -> [String] {
        event.attendees.map { attendee in
            let name = attendee.personId.flatMap { id in people.first(where: { $0.id == id })?.name } ?? attendee.name ?? "Гість"
            let status = Self.attendeeStatusText(attendee.status)
            return status.isEmpty ? name : "\(name) (\(status))"
        }
    }

    private func organizerText(_ live: OrbitCalendarEvent?) -> String {
        guard let organizer = live?.organizer else { return "Не вказано" }
        if let id = organizer.personId, let name = names(for: [id]).first { return name }
        return organizer.external == true ? "Зовнішній організатор" : "Не вказано"
    }

    /// Pull-to-refresh: ask the server to refresh its iCloud mirror for the visible window first (read-only, rate limited), then reload.
    private func refreshMirrorThenLoad() async {
        let start = calendar.startOfDay(for: referenceDate)
        let from = calendar.date(byAdding: .day, value: -7, to: start) ?? start
        let to = calendar.date(byAdding: .day, value: 62, to: start) ?? start
        await MainProductAPI.shared.refreshCalendarNow(from: from, to: to)
        await load()
    }

    private func jumpToToday() {
        displayMode = .week
        visibleMonth = ConceptCalendarDates.monthStart(referenceDate)
        selectAgendaDay(referenceDate, loadRange: true)
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
    let calendarOwnerIDs: [String]
    let attendees: [OrbitCalendarAttendee]

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
        self.calendarOwnerIDs = []
        self.attendees = []
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
        calendarOwnerIDs = apiEvent.calendarOwners ?? []
        attendees = apiEvent.attendees ?? []
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
    static func weekdayInitial(_ date: Date) -> String { formatter("EEEEE").string(from: date).uppercased() }
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
