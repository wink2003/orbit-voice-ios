import SwiftUI

// Medical UX expansion of family-ai#379.
// Presentation only: existing /api/medical is the sole live source.
// Future modules are explicitly labelled and never invent patient records,
// request broader permissions, or grant Chat/Voice/Agent access.
private enum MedicalUXTab: String, CaseIterable, Identifiable {
    case overview = "Огляд"
    case medications = "Ліки"
    case visits = "Прийоми"
    case history = "Історія"
    case documents = "Документи"
    case more = "Ще"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .medications: "pills"
        case .visits: "calendar"
        case .history: "clock.arrow.circlepath"
        case .documents: "doc.text"
        case .more: "square.grid.3x3"
        }
    }
}

private struct MedicalUXFuture: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let description: String
    let capabilities: [String]

    static let catalog: [Self] = [
        .init(id: "measurements", title: "Показники", subtitle: "Графіки й динаміка",
              symbol: "chart.xyaxis.line",
              description: "Динаміка вимірювань за датами, одиницями та джерелами — без автоматичного трактування результатів.",
              capabilities: ["Артеріальний тиск, пульс, температура, вага", "Графіки й фільтр за періодом", "Позначення джерела та дати вимірювання"]),
        .init(id: "labs", title: "Аналізи", subtitle: "Результати й порівняння",
              symbol: "testtube.2",
              description: "Зручне сховище лабораторних результатів з оригіналом документа й історією змін.",
              capabilities: ["Параметри та одиниці вимірювання", "Діапазони лише з джерела лабораторії", "Порівняння в часі з посиланням на документ"]),
        .init(id: "prescriptions", title: "Рецепти", subtitle: "Е-рецепти та повторення",
              symbol: "cross.vial",
              description: "Особистий список рецептів, термінів дії та запитів на повторення.",
              capabilities: ["Прив'язка до ліків і лікаря", "Термін дії рецепта", "Підготовка запиту без автоматичного надсилання"]),
        .init(id: "vaccinations", title: "Щеплення", subtitle: "Історія вакцинацій",
              symbol: "syringe",
              description: "Історія щеплень за підтвердженими документами.",
              capabilities: ["Препарат, дата, серія і джерело", "Скан Impfpass", "Нагадування лише за підтвердженим планом"]),
        .init(id: "symptoms", title: "Самопочуття", subtitle: "Симптоми та нотатки",
              symbol: "waveform.path.ecg",
              description: "Щоденник самопочуття, який зручно показати лікарю.",
              capabilities: ["Час появи й тривалість", "Нотатки, фото, контекст", "Вибірковий експорт для лікаря"]),
        .init(id: "passport", title: "Медичний паспорт", subtitle: "Важливе в одному місці",
              symbol: "person.text.rectangle",
              description: "Коротка перевірена картка для прийому: тільки дані, які людина сама дозволила показувати.",
              capabilities: ["Алергії та важливі стани", "Поточні ліки й контакти", "Контрольований експорт без розкриття зайвого"]),
        .init(id: "care-plan", title: "План лікування", subtitle: "Курс, кроки, контроль",
              symbol: "checklist",
              description: "Організаційний план, заснований на призначеннях лікаря, а не на рішеннях AI.",
              capabilities: ["Термін курсу та план перевірки", "Нотатки про виконання", "Посилання на призначення"]),
        .init(id: "doctors", title: "Лікарі та клініки", subtitle: "Контакти й маршрути",
              symbol: "stethoscope",
              description: "Приватна адресна книга медичних закладів.",
              capabilities: ["Спеціалізація, адреса, контакти", "Прив'язка до відвідувань", "Без автоматичного надсилання персональних даних"]),
        .init(id: "insurance", title: "Страхування", subtitle: "Картки та довідки",
              symbol: "checkmark.shield",
              description: "Документи й контакти страхової компанії з мінімальним обсягом чутливих даних.",
              capabilities: ["Страхова компанія та контакти", "Документи й терміни дії", "Без зберігання секретів у відкритому тексті"]),
        .init(id: "preparation", title: "До лікаря", subtitle: "Питання й чекліст",
              symbol: "list.clipboard",
              description: "Підготовка до конкретного візиту без самостійної постановки діагнозу.",
              capabilities: ["Список питань", "Які документи взяти", "Підсумок після прийому"]),
        .init(id: "medication-log", title: "Журнал прийому", subtitle: "Прийнято / пропущено",
              symbol: "pills.circle",
              description: "Окремий факт прийому ліків, не плутати з наявним розкладом призначень.",
              capabilities: ["Підтвердження фактичного прийому", "Історія та нагадування", "Явна відмінність призначення і факту"]),
        .init(id: "export", title: "Медична папка", subtitle: "Експорт для прийому",
              symbol: "square.and.arrow.up",
              description: "Обрані документи та записи, які власник сам дозволяє експортувати.",
              capabilities: ["Вибір людини й періоду", "Попередній перегляд", "Ручне підтвердження перед поширенням"])
    ]
}

@MainActor
struct MedicalExperienceView: View {
    @State private var subjects: [MedSubject] = []
    @State private var selectedSubjectID: String?
    @State private var summary: MedSummary?
    @State private var loadingPeople = true
    @State private var loadingSummary = false
    @State private var subjectsError: String?
    @State private var summaryError: String?
    @State private var tab: MedicalUXTab = .overview
    @State private var showingPrivacy = false
    @State private var documentQuery = ""
    @State private var documentFilter = "Усі"

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private var selectedSubject: MedSubject? {
        subjects.first { $0.id == selectedSubjectID }
    }

    private var validSummary: MedSummary? {
        guard summary?.subject.id == selectedSubjectID else { return nil }
        return summary
    }

    private var upcomingVisits: [MedAppointment] {
        let now = Date()
        return (validSummary?.appointments ?? [])
            .filter { item in
                guard let date = appointmentDate(item.startsAt) else { return false }
                return date >= now && item.status.lowercased() != "cancelled"
            }
            .sorted {
                (appointmentDate($0.startsAt) ?? .distantFuture) <
                (appointmentDate($1.startsAt) ?? .distantFuture)
            }
    }

    private var filteredDocuments: [MedDocument] {
        (validSummary?.documents ?? []).filter { document in
            let matchesText = documentQuery.isEmpty ||
                document.title.localizedCaseInsensitiveContains(documentQuery) ||
                document.filename.localizedCaseInsensitiveContains(documentQuery)
            return matchesText && (documentFilter == "Усі" ||
                document.kind.localizedCaseInsensitiveContains(documentFilter))
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                heading
                if loadingPeople {
                    MedicalUXCard {
                        ProgressView("Завантаження доступних профілів…")
                            .frame(maxWidth: .infinity, minHeight: 90)
                    }
                } else if let subjectsError {
                    restrictedCard(subjectsError)
                } else if subjects.isEmpty {
                    emptyPeopleCard
                } else {
                    peoplePicker
                    sectionPicker
                    if loadingSummary {
                        MedicalUXCard {
                            ProgressView("Завантаження медичної картки…")
                                .frame(maxWidth: .infinity, minHeight: 90)
                        }
                    } else if let summaryError {
                        restrictedCard(summaryError)
                    } else if validSummary != nil {
                        selectedContent
                    }
                    privacyFootnote
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .background(Routes05Tokens.canvas.ignoresSafeArea())
        .foregroundStyle(Routes05Tokens.ink)
        .navigationTitle("Здоров'я")
        .navigationBarTitleDisplayMode(.inline)
        .routes05NativeSwipeBack()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingPrivacy = true } label: {
                    Image(systemName: "lock.shield")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Приватність медичних даних")
            }
        }
        .sheet(isPresented: $showingPrivacy) {
            NavigationStack { MedicalUXPrivacyView() }
        }
        .task { await loadSubjects() }
        .task(id: selectedSubjectID) {
            guard let selectedSubjectID else { return }
            await loadSummary(selectedSubjectID)
        }
        .refreshable { await reload() }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(Routes05Tokens.accentInk)
                    .background(Routes05Tokens.mint, in: RoundedRectangle(cornerRadius: 7))
                Text("ORBIT / HEALTH")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                Spacer()
                Label("Приватно", systemImage: "lock.fill")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Routes05Tokens.lilac.opacity(0.28), in: Capsule())
            }
            Text("Здоров'я.\nВсе важливе поруч.")
                .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                .tracking(-0.8)
                .fixedSize(horizontal: false, vertical: true)
            Text("Ліки, прийоми, діагнози та медичні документи — окремо для кожної людини.")
                .font(.subheadline)
                .foregroundStyle(Routes05Tokens.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var peoplePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            MedicalUXHeading(title: "Чия картка?", subtitle: "Лише профілі, доступні вам за правами Orbit")
            ScrollView(.horizontal) {
                HStack(spacing: 9) {
                    ForEach(subjects) { subject in
                        Button {
                            guard selectedSubjectID != subject.id else { return }
                            selectedSubjectID = subject.id
                            summary = nil
                            summaryError = nil
                            tab = .overview
                            documentQuery = ""
                            documentFilter = "Усі"
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(subject.displayName)
                                    .font(.subheadline.weight(.bold))
                                    .lineLimit(1)
                                Text(subject.kind == "external" ? (subject.relation ?? "Запис без акаунта") : "Профіль Orbit")
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 13)
                            .frame(minWidth: 130, minHeight: 57, alignment: .leading)
                            .foregroundStyle(selectedSubjectID == subject.id ? Routes05Tokens.accentInk : Routes05Tokens.ink)
                            .background(selectedSubjectID == subject.id ? Routes05Tokens.mint : Routes05Tokens.surface,
                                        in: RoundedRectangle(cornerRadius: 9))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(selectedSubjectID == subject.id ? Routes05Tokens.ink : Routes05Tokens.rule,
                                            lineWidth: selectedSubjectID == subject.id ? 1.5 : 0.7)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedSubjectID == subject.id ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 7) {
                Image(systemName: "lock.fill").font(.caption2)
                Text("Медичні записи не передаються в чат або Voice.")
                    .font(.caption)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Routes05Tokens.secondary)
            NavigationLink {
                MedicalHomeView()
            } label: {
                Label("Керувати медичними картками", systemImage: "person.2.badge.gearshape")
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: 44, alignment: .leading)
            }
        }
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(MedicalUXTab.allCases) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) { tab = section }
                    } label: {
                        Label(section.rawValue, systemImage: section.symbol)
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 13)
                            .frame(minHeight: 43)
                            .foregroundStyle(tab == section ? Routes05Tokens.darkSurfaceInk : Routes05Tokens.ink)
                            .background(tab == section ? Routes05Tokens.darkSurface : Routes05Tokens.surface,
                                        in: Capsule())
                            .overlay {
                                Capsule().stroke(tab == section ? Color.clear : Routes05Tokens.rule, lineWidth: 0.7)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tab == section ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Розділи здоров'я")
    }

    @ViewBuilder private var selectedContent: some View {
        switch tab {
        case .overview: overviewPage
        case .medications: medicationPage
        case .visits: visitsPage
        case .history: historyPage
        case .documents: documentsPage
        case .more: servicesPage
        }
    }

    private var overviewPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            nextStep
            quickAccess
            snapshotMetrics
            livePreview
            futurePreview
        }
    }

    @ViewBuilder private var nextStep: some View {
        if let next = upcomingVisits.first {
            VStack(alignment: .leading, spacing: 12) {
                Label("НАСТУПНИЙ ПРИЙОМ", systemImage: "calendar")
                    .font(.caption.weight(.heavy))
                Text(next.title)
                    .font(.title2.weight(.bold))
                if let date = appointmentDate(next.startsAt) {
                    Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute().locale(Locale(identifier: "uk_UA"))))
                        .font(.subheadline.weight(.medium))
                }
                Text([next.provider, next.location].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(Routes05Tokens.accentInk.opacity(0.75))
                if let selectedSubject {
                    NavigationLink {
                        MedicalSubjectView(subject: selectedSubject)
                    } label: {
                        Label("Відкрити записи та підготовку", systemImage: "arrow.up.right")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 47)
                            .foregroundStyle(Routes05Tokens.darkSurfaceInk)
                            .background(Routes05Tokens.darkSurface, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Routes05Tokens.accentInk)
            .background(Routes05Tokens.mint, in: RoundedRectangle(cornerRadius: 11))
        } else {
            MedicalUXCard(accent: Routes05Tokens.mint) {
                Label("Що далі?", systemImage: "calendar.badge.clock")
                    .font(.headline.weight(.bold))
                Text("Майбутніх прийомів із підтвердженою датою зараз немає.")
                    .font(.subheadline)
                    .foregroundStyle(Routes05Tokens.secondary)
                Text("Це не означає, що медична допомога не потрібна.")
                    .font(.caption)
                    .foregroundStyle(Routes05Tokens.secondary)
            }
        }
    }

    private var quickAccess: some View {
        VStack(alignment: .leading, spacing: 11) {
            MedicalUXHeading(title: "Швидкий доступ", subtitle: "Діючі записи Orbit")
            LazyVGrid(columns: columns, spacing: 10) {
                actionTile("Ліки", symbol: "pills", tint: Routes05Tokens.yellow, destination: .medications)
                actionTile("Прийоми", symbol: "calendar", tint: Routes05Tokens.mint, destination: .visits)
                actionTile("Діагнози", symbol: "heart.text.square", tint: Routes05Tokens.lilac, destination: .history)
                actionTile("Документи", symbol: "doc.text", tint: Routes05Tokens.blue.opacity(0.35), destination: .documents)
            }
        }
    }

    private func actionTile(_ title: String, symbol: String, tint: Color, destination: MedicalUXTab) -> some View {
        Button { withAnimation { tab = destination } } label: {
            VStack(alignment: .leading, spacing: 15) {
                Image(systemName: symbol).font(.title3.weight(.medium))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(Routes05Tokens.accentInk)
                    .background(tint, in: RoundedRectangle(cornerRadius: 9))
                HStack {
                    Text(title).font(.subheadline.weight(.bold))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 111, alignment: .leading)
            .foregroundStyle(Routes05Tokens.ink)
            .background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10).stroke(Routes05Tokens.rule, lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }

    private var snapshotMetrics: some View {
        VStack(alignment: .leading, spacing: 11) {
            MedicalUXHeading(title: "Коротко про картку", subtitle: "Лише дані поточного профілю")
            LazyVGrid(columns: columns, spacing: 10) {
                countTile("Ліки", value: validSummary?.medications.count ?? 0, symbol: "pills")
                countTile("Прийоми", value: validSummary?.appointments.count ?? 0, symbol: "calendar")
                countTile("Діагнози", value: validSummary?.diagnoses.count ?? 0, symbol: "cross.case")
                countTile("Документи", value: validSummary?.documents.count ?? 0, symbol: "doc.on.doc")
            }
        }
    }

    private func countTile(_ title: String, value: Int, symbol: String) -> some View {
        MedicalUXCard {
            Image(systemName: symbol).foregroundStyle(Routes05Tokens.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text("\(value)").font(.system(size: 30, weight: .heavy, design: .rounded))
                Spacer()
                Text(title).font(.caption).foregroundStyle(Routes05Tokens.secondary)
            }
        }
    }

    private var livePreview: some View {
        VStack(alignment: .leading, spacing: 11) {
            MedicalUXHeading(title: "Поточна інформація", subtitle: "Збережено в /api/medical")
            MedicalUXCard(accent: Routes05Tokens.yellow) {
                Text("ЛІКИ").font(.caption.weight(.heavy)).tracking(1)
                if let first = validSummary?.medications.first {
                    Text(first.name).font(.headline.weight(.bold))
                    Text([first.doseText, first.schedule?.times?.joined(separator: ", ")].compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(Routes05Tokens.secondary)
                } else {
                    Text("Ліки не додані").foregroundStyle(Routes05Tokens.secondary)
                }
                Button("Переглянути всі ліки") { tab = .medications }
                    .font(.footnote.weight(.semibold))
            }
            MedicalUXCard(accent: Routes05Tokens.lilac) {
                Text("ДІАГНОЗИ").font(.caption.weight(.heavy)).tracking(1)
                if let first = validSummary?.diagnoses.first {
                    Text(first.name).font(.headline.weight(.bold))
                    Text(first.status).font(.footnote).foregroundStyle(Routes05Tokens.secondary)
                } else {
                    Text("Діагнозів не додано").foregroundStyle(Routes05Tokens.secondary)
                }
                Button("Переглянути медичну історію") { tab = .history }
                    .font(.footnote.weight(.semibold))
            }
        }
    }

    private var futurePreview: some View {
        VStack(alignment: .leading, spacing: 11) {
            MedicalUXHeading(title: "Більше можливостей", subtitle: "Продумано для наступних етапів")
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(MedicalUXFuture.catalog.prefix(4))) { feature in
                    futureTile(feature)
                }
            }
            Button("Подивитися всі майбутні модулі") { tab = .more }
                .font(.footnote.weight(.semibold))
                .frame(minHeight: 44, alignment: .leading)
        }
    }

    private var medicationPage: some View {
        VStack(alignment: .leading, spacing: 13) {
            MedicalUXHeading(title: "Ліки й призначення", subtitle: "Розклад — не підтвердження факту прийому")
            if let list = validSummary?.medications, !list.isEmpty {
                ForEach(list) { medication in
                    MedicalUXCard(accent: medication.status == "active" ? Routes05Tokens.yellow : Routes05Tokens.rule) {
                        HStack {
                            Text(medication.name).font(.headline.weight(.bold))
                            Spacer()
                            Text(medication.status == "active" ? "Активні" : medication.status)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Routes05Tokens.secondary)
                        }
                        if let dose = medication.doseText, !dose.isEmpty {
                            Label(dose, systemImage: "pills")
                                .font(.subheadline)
                        }
                        if let times = medication.schedule?.times, !times.isEmpty {
                            Label(times.joined(separator: ", "), systemImage: "clock")
                                .font(.subheadline)
                        }
                        if medication.schedule?.asNeeded == true {
                            Text("За потреби · лише за призначенням")
                                .font(.footnote).foregroundStyle(Routes05Tokens.secondary)
                        }
                        if let instructions = medication.instructions, !instructions.isEmpty {
                            Text(instructions).font(.footnote).foregroundStyle(Routes05Tokens.secondary)
                        }
                    }
                }
            } else {
                MedicalUXEmpty(title: "Поки немає записів про ліки", symbol: "pills")
            }
            manageRecordsLink("Додати або змінити ліки")
            if let feature = MedicalUXFuture.catalog.first(where: { $0.id == "medication-log" }) {
                futureTile(feature)
            }
        }
    }

    private var visitsPage: some View {
        VStack(alignment: .leading, spacing: 13) {
            MedicalUXHeading(title: "Прийоми лікарів", subtitle: "Дати, заклади й підготовка")
            if let list = validSummary?.appointments, !list.isEmpty {
                ForEach(list) { visit in
                    MedicalUXCard(accent: Routes05Tokens.mint) {
                        Text(visit.title).font(.headline.weight(.bold))
                        if let startsAt = appointmentDate(visit.startsAt) {
                            Label(startsAt.formatted(.dateTime.day().month().year().hour().minute().locale(Locale(identifier: "uk_UA"))),
                                  systemImage: "calendar").font(.subheadline)
                        }
                        if let provider = visit.provider, !provider.isEmpty {
                            Label(provider, systemImage: "stethoscope").font(.subheadline)
                        }
                        if let location = visit.location, !location.isEmpty {
                            Label(location, systemImage: "mappin").font(.footnote)
                        }
                        Text(visit.status).font(.caption).foregroundStyle(Routes05Tokens.secondary)
                    }
                }
            } else {
                MedicalUXEmpty(title: "Запланованих прийомів ще немає", symbol: "calendar")
            }
            manageRecordsLink("Додати або змінити прийом")
            if let feature = MedicalUXFuture.catalog.first(where: { $0.id == "preparation" }) {
                futureTile(feature)
            }
        }
    }

    private var historyPage: some View {
        VStack(alignment: .leading, spacing: 13) {
            MedicalUXHeading(title: "Медична історія", subtitle: "Підтверджені записи та майбутня хронологія")
            if let list = validSummary?.diagnoses, !list.isEmpty {
                ForEach(list) { diagnosis in
                    MedicalUXCard(accent: Routes05Tokens.lilac) {
                        Text(diagnosis.name).font(.headline.weight(.bold))
                        HStack {
                            if let code = diagnosis.code, !code.isEmpty {
                                Text(code).font(.footnote.monospaced())
                            }
                            Text(diagnosis.status).font(.footnote)
                        }
                        .foregroundStyle(Routes05Tokens.secondary)
                        if let notes = diagnosis.notes, !notes.isEmpty {
                            Text(notes).font(.subheadline)
                        }
                    }
                }
            } else {
                MedicalUXEmpty(title: "Діагнозів у картці немає", symbol: "heart.text.square")
            }
            manageRecordsLink("Додати або змінити діагноз")
            ForEach(MedicalUXFuture.catalog.filter { ["symptoms", "care-plan", "passport"].contains($0.id) }) {
                futureTile($0)
            }
        }
    }

    private var documentsPage: some View {
        VStack(alignment: .leading, spacing: 13) {
            MedicalUXHeading(title: "Медична папка", subtitle: "Скани й документи із захищеного сховища Orbit")
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Routes05Tokens.secondary)
                TextField("Назва або ім'я файлу", text: $documentQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Пошук медичних документів")
            }
            .padding(13)
            .background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(Routes05Tokens.rule, lineWidth: 0.7) }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(["Усі", "report", "lab", "prescription", "vaccination", "other"], id: \.self) { filter in
                        Button {
                            documentFilter = filter
                        } label: {
                            Text(documentFilterLabel(filter))
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 40)
                                .background(documentFilter == filter ? Routes05Tokens.mint : Routes05Tokens.surface,
                                            in: Capsule())
                                .foregroundStyle(documentFilter == filter ? Routes05Tokens.accentInk : Routes05Tokens.ink)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
            if filteredDocuments.isEmpty {
                MedicalUXEmpty(title: "Документів за цими умовами немає", symbol: "doc.text")
            } else {
                ForEach(filteredDocuments) { document in
                    MedicalUXCard(accent: Routes05Tokens.blue) {
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: "doc.text")
                                .font(.title3)
                                .foregroundStyle(Routes05Tokens.blue)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(document.title).font(.headline.weight(.semibold))
                                Text("\(document.filename) · \(document.sizeBytes / 1024) КБ")
                                    .font(.caption).foregroundStyle(Routes05Tokens.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                Text("Відкрити або поділитися оригіналом можна в існуючій медичній картці.")
                    .font(.footnote).foregroundStyle(Routes05Tokens.secondary)
            }
            manageRecordsLink("Відкрити документи / додати скан")
        }
    }

    private func documentFilterLabel(_ key: String) -> String {
        switch key {
        case "report": "Висновки"
        case "lab": "Аналізи"
        case "prescription": "Рецепти"
        case "vaccination": "Щеплення"
        case "other": "Інше"
        default: "Усі"
        }
    }

    private var servicesPage: some View {
        VStack(alignment: .leading, spacing: 13) {
            MedicalUXHeading(title: "Усе для здоров'я", subtitle: "Заплановані модулі, для яких ще потрібен backend")
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(MedicalUXFuture.catalog) { feature in futureTile(feature) }
            }
            MedicalUXCard(accent: Routes05Tokens.lilac) {
                Label("Режим проєктування", systemImage: "hammer")
                    .font(.headline.weight(.semibold))
                Text("Ці екрани пояснюють майбутню функціональність. Вони не створюють медичних записів і не звертаються до зовнішніх сервісів.")
                    .font(.footnote).foregroundStyle(Routes05Tokens.secondary)
            }
        }
    }

    private func futureTile(_ feature: MedicalUXFuture) -> some View {
        NavigationLink {
            MedicalUXFutureDetail(feature: feature)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: feature.symbol)
                    .font(.title3)
                    .foregroundStyle(Routes05Tokens.blue)
                Text(feature.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Routes05Tokens.ink)
                    .multilineTextAlignment(.leading)
                Text(feature.subtitle)
                    .font(.caption)
                    .foregroundStyle(Routes05Tokens.secondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Text("ЗАПЛАНОВАНО")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(Routes05Tokens.secondary)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
            .background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Routes05Tokens.rule, lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Переглянути концепцію майбутньої функції")
    }

    @ViewBuilder
    private func manageRecordsLink(_ title: String) -> some View {
        if let selectedSubject {
            NavigationLink {
                MedicalSubjectView(subject: selectedSubject)
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .foregroundStyle(Routes05Tokens.darkSurfaceInk)
                .background(Routes05Tokens.darkSurface, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyPeopleCard: some View {
        MedicalUXCard(accent: Routes05Tokens.mint) {
            Label("Немає доступних медичних карток", systemImage: "person.crop.circle.badge.questionmark")
                .font(.headline)
            Text("Список повертає Orbit. Додавання людини та її права залишаються в чинному медичному модулі.")
                .font(.subheadline).foregroundStyle(Routes05Tokens.secondary)
            NavigationLink {
                MedicalHomeView()
            } label: {
                Label("Керувати людьми", systemImage: "person.crop.circle.badge.plus")
                    .frame(minHeight: 44, alignment: .leading)
            }
        }
    }

    private func restrictedCard(_ message: String) -> some View {
        MedicalUXCard(accent: Routes05Tokens.orange) {
            Label("Медичні дані недоступні", systemImage: "lock.shield")
                .font(.headline.weight(.semibold))
            Text(message).font(.subheadline)
            Text("Дані не показуються з кешу або з інших профілів. Права вирішує сервер.")
                .font(.caption).foregroundStyle(Routes05Tokens.secondary)
            Button("Повторити перевірку") {
                Task { await loadSubjects() }
            }
            .font(.footnote.weight(.semibold))
            .frame(minHeight: 44)
        }
    }

    private var privacyFootnote: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "lock.shield.fill")
            Text("Медичні дані доступні лише в межах дозволів Orbit. Нові модулі не активні; автоматичних висновків, змін призначень та доступу Core Agent немає.")
                .font(.footnote)
        }
        .foregroundStyle(Routes05Tokens.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func appointmentDate(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: iso) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: iso)
    }

    private func loadSubjects() async {
        loadingPeople = true
        subjectsError = nil
        defer { loadingPeople = false }
        do {
            let permitted = try await MedicalAPI.subjects()
            subjects = permitted
            if let current = selectedSubjectID, permitted.contains(where: { $0.id == current }) {
                await loadSummary(current)
            } else {
                summary = nil
                selectedSubjectID = permitted.first?.id
            }
        } catch {
            subjects = []
            selectedSubjectID = nil
            summary = nil
            subjectsError = MedicalAPI.message(for: error)
        }
    }

    private func reload() async {
        await loadSubjects()
    }

    private func loadSummary(_ id: String) async {
        loadingSummary = true
        summaryError = nil
        summary = nil
        defer {
            if selectedSubjectID == id { loadingSummary = false }
        }
        do {
            let result = try await MedicalAPI.summary(id)
            guard selectedSubjectID == id else { return }
            summary = result
        } catch {
            guard selectedSubjectID == id else { return }
            summaryError = MedicalAPI.message(for: error)
        }
    }
}

private struct MedicalUXCard<Content: View>: View {
    var accent: Color = Routes05Tokens.mint
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent)
                    .frame(width: 4)
                    .padding(.vertical, 14)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Routes05Tokens.rule, lineWidth: 0.7)
            }
    }
}

private struct MedicalUXHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.heavy))
                .foregroundStyle(Routes05Tokens.ink)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(Routes05Tokens.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MedicalUXEmpty: View {
    let title: String
    let symbol: String

    var body: some View {
        MedicalUXCard {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(Routes05Tokens.secondary)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Routes05Tokens.secondary)
            }
            .frame(minHeight: 54)
        }
    }
}

private struct MedicalUXFutureDetail: View {
    let feature: MedicalUXFuture

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("ПРОЄКТУЄТЬСЯ · BACKEND НЕ ПІДКЛЮЧЕНИЙ",
                      systemImage: "hammer")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Routes05Tokens.secondary)
                Image(systemName: feature.symbol)
                    .font(.system(size: 35))
                    .foregroundStyle(Routes05Tokens.blue)
                    .padding(.top, 5)
                Text(feature.title).font(.largeTitle.weight(.heavy))
                Text(feature.description)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                MedicalUXCard(accent: Routes05Tokens.lilac) {
                    Text("Що передбачено")
                        .font(.headline.weight(.semibold))
                    ForEach(feature.capabilities, id: \.self) { capability in
                        Label(capability, systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                MedicalUXCard(accent: Routes05Tokens.orange) {
                    Text("Неактивно")
                        .font(.headline.weight(.semibold))
                    Text("Це майбутня функція. Тут немає реальних вимірювань, автоматичних медичних висновків або прихованих записів у backend.")
                        .font(.subheadline)
                        .foregroundStyle(Routes05Tokens.secondary)
                }
            }
            .padding(16)
        }
        .background(Routes05Tokens.canvas.ignoresSafeArea())
        .foregroundStyle(Routes05Tokens.ink)
        .navigationTitle(feature.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MedicalUXPrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Routes05Tokens.blue)
                Text("Особисте залишається особистим")
                    .font(.title2.weight(.heavy))
                MedicalUXCard(accent: Routes05Tokens.mint) {
                    Label("Доступ перевіряє backend", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.headline)
                    Text("Список карток і записи завантажуються лише через наявний MedicalAPI. Якщо доступ відхилено, медичні дані не відображаються.")
                        .font(.subheadline).foregroundStyle(Routes05Tokens.secondary)
                }
                MedicalUXCard(accent: Routes05Tokens.lilac) {
                    Label("Родинні записи не змішуються", systemImage: "person.2")
                        .font(.headline)
                    Text("Зовнішні родичі мають власні записи без створення Orbit-акаунта; server ACL визначає, хто може їх читати.")
                        .font(.subheadline).foregroundStyle(Routes05Tokens.secondary)
                }
                MedicalUXCard(accent: Routes05Tokens.yellow) {
                    Label("AI та Voice не підключені", systemImage: "hand.raised")
                        .font(.headline)
                    Text("Цей інтерфейс не додає доступу Core Agent, Voice, HealthKit або стороннім медичним сервісам.")
                        .font(.subheadline).foregroundStyle(Routes05Tokens.secondary)
                }
                Text("Експорт, спільний доступ і майбутні consequential actions потребуватимуть окремих дозволів та підтвердження.")
                    .font(.footnote).foregroundStyle(Routes05Tokens.secondary)
            }
            .padding(16)
        }
        .background(Routes05Tokens.canvas.ignoresSafeArea())
        .foregroundStyle(Routes05Tokens.ink)
        .navigationTitle("Приватність")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Готово") { dismiss() }
            }
        }
    }
}
