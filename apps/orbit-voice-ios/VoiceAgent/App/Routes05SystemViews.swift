import SwiftUI

/// ROUTES 05 presentation for the Core/System/Discovery routes that are not
/// owned by the School Hub.  Production feature stores remain authoritative;
/// this view is also used by the DEBUG route harness so screenshots exercise
/// native SwiftUI surfaces instead of UIKit alerts or legacy placeholder chrome.
struct Routes05SystemRouteView: View {
    let routeID: String

    @State private var selectedFilter = "Всі"
    @State private var query = ""
    @State private var draft = ""
    @State private var confirmed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Routes05Mast(section: section)
                routeBody
            }
            .padding(.bottom, 28)
        }
        .background(Routes05Tokens.canvas.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("routes05.\(routeID)")
    }

    private var section: String {
        switch routeID {
        case "settings", "integrations", "memorydetail", "contactdetail", "actionconfirm", "admin", "voice", "familychat": "system"
        default: "core"
        }
    }

    @ViewBuilder
    private var routeBody: some View {
        switch routeID {
        case "calendar": calendar
        case "contacts": contacts
        case "memory": memory
        case "voice": voice
        case "familychat": familyChat
        case "settings", "profile": settings
        case "integrations": integrations
        case "memorydetail": memoryDetail
        case "contactdetail": contactDetail
        case "actionconfirm": actionConfirm
        case "admin": admin
        case "notifications": notifications
        case "memoryimports": memoryImports
        default: Routes05UnavailableView(routeID: routeID)
        }
    }

    private var calendar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Routes05Chapter("ORBIT / 06", title: "Календар", detail: "Родинні та підключені події; шкільні — окремо.", accent: Routes05Tokens.yellow)
            filterPills(["Всі", "Сімейні", "Мої"])
            Routes05SectionHeader("22–28 жовтня", action: "Шкільні події ↗") {}
                .padding(.horizontal, 16).padding(.top, 26)
            HStack(spacing: 8) {
                day("ЧТ", "22", active: true)
                day("ПТ", "23", active: false)
                day("СБ", "24", active: false)
                day("НД", "25", active: false)
            }
            .padding(.horizontal, 16).padding(.top, 12)
            Routes05Rail {
                VStack(alignment: .leading, spacing: 22) {
                    event("13:40 · ШКОЛА", title: "Schwimm-AG", detail: "Шкільна подія у своєму джерелі", tint: Routes05Tokens.yellow)
                    event("15:00 · СІМ’Я", title: "Сімейна зустріч", detail: "Особистий календар", tint: Routes05Tokens.yellow)
                    event("СУБОТА / 24", title: "Вільний день", detail: "Немає інших подій", tint: Routes05Tokens.yellow)
                }
            }
            .padding(.top, 30)
            darkAction("НОВА ПОДІЯ", detail: "Після підтвердження") {}
                .padding(.top, 22)
        }
    }

    private func day(_ weekday: String, _ number: String, active: Bool) -> some View {
        VStack(spacing: 5) {
            Text(weekday).font(.caption.weight(.black))
            Text(number).font(.system(size: 39, weight: .black, design: .rounded))
        }
        .frame(maxWidth: .infinity, minHeight: 108)
        .foregroundStyle(Routes05Tokens.ink)
        .background(active ? Routes05Tokens.yellow : Routes05Tokens.surface)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Routes05Tokens.ink, lineWidth: 1.5))
    }

    private func event(_ eyebrow: String, title: String, detail: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Circle().fill(tint).frame(width: 24, height: 24).overlay(Circle().stroke(Routes05Tokens.ink, lineWidth: 2))
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow).font(.system(size: 10, weight: .black, design: .monospaced)).tracking(0.8)
                Text(title).font(.headline.weight(.black))
                Text(detail).font(.subheadline).foregroundStyle(Routes05Tokens.secondary)
            }
        }
    }

    private var contacts: some View {
        VStack(alignment: .leading, spacing: 0) {
            Routes05Chapter("ORBIT / 07", title: "Контакти", detail: "Особисті та сімейні контакти зі своїми дозволами.", accent: Routes05Tokens.yellow)
            searchField("Знайти людину")
            filterPills(["Всі", "Особисті", "Сімейні"])
            contactRow("А", "Анна · близькі", "Збережений контакт · WhatsApp", Routes05Tokens.mint)
            contactRow("П", "Павло · родина", "Telegram · явна ідентичність", Routes05Tokens.lilac)
            contactRow("М", "Марія · колеги", "Особистий контакт", Routes05Tokens.yellow)
            darkAction("+ НОВИЙ КОНТАКТ", detail: "→") {}
                .padding(.top, 12)
            Text("Доступ ідентичностей визначає сервер.")
                .font(.caption).foregroundStyle(Routes05Tokens.secondary).padding(.horizontal, 16).padding(.top, 14)
        }
    }

    private func contactRow(_ initial: String, _ title: String, _ detail: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Text(initial).font(.title2.weight(.black)).frame(width: 48, height: 48).background(tint, in: Circle()).overlay(Circle().stroke(Routes05Tokens.ink, lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline.weight(.black)); Text(detail).font(.subheadline).foregroundStyle(Routes05Tokens.secondary) }
            Spacer(); Image(systemName: "arrow.up.right").font(.headline.weight(.black))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Routes05Tokens.rule).frame(height: 1) }
        .foregroundStyle(Routes05Tokens.ink)
    }

    private var memory: some View {
        VStack(alignment: .leading, spacing: 0) {
            Routes05Chapter("ORBIT / 08", title: "Пам’ять", detail: "Факти з provenance, профілем і часовою історією.", accent: Routes05Tokens.lilac)
            Routes05Hero(accent: Routes05Tokens.lilac) { VStack(alignment: .leading, spacing: 8) { Text("ПРИВАТНО / VERIFIED").font(.caption.weight(.black)); Text("Збережені факти").font(.title2.weight(.black)); Text("Переглядайте, уточнюйте або відкликайте лише дозволені записи.").font(.subheadline) } }
            Routes05SectionHeader("Останні факти", action: "Імпорти ↗") {}.padding(.horizontal, 16).padding(.top, 24)
            memoryRow("Уподобання", "Чай з м’ятою", "підтверджено сьогодні", Routes05Tokens.mint)
            memoryRow("Школа", "5F · Lina", "джерело: Schulmanager", Routes05Tokens.yellow)
            memoryRow("Сім’я", "Спільний маршрут", "актуально для профілю", Routes05Tokens.lilac)
        }
    }

    private func memoryRow(_ title: String, _ value: String, _ detail: String, _ tint: Color) -> some View {
        Routes05Ticket(tint: tint) { VStack(alignment: .leading, spacing: 3) { Text(title).font(.caption.weight(.black)); Text(value).font(.headline.weight(.black)); Text(detail).font(.caption).foregroundStyle(Routes05Tokens.secondary) } }
            .padding(.horizontal, 16)
    }

    private var voice: some View {
        VStack(alignment: .leading, spacing: 0) {
            Routes05Chapter("SYSTEM / 17", title: "Голос", detail: "LiveKit і звуковий стан цього пристрою.", accent: Routes05Tokens.orange)
            Routes05Hero(accent: Routes05Tokens.darkSurface) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("LIVEKIT / READY").font(.caption.weight(.black)).foregroundStyle(Routes05Tokens.mint)
                    Text("Говоріть з Orbit.").font(.largeTitle.weight(.black)).foregroundStyle(Routes05Tokens.darkSurfaceInk)
                    Text("Сесія запускається через існуючий voice lifecycle.").font(.subheadline).foregroundStyle(Routes05Tokens.darkSurfaceInk)
                    Button("ПОЧАТИ ГОЛОС ↗") {}.buttonStyle(.borderedProminent).tint(Routes05Tokens.yellow).foregroundStyle(Routes05Tokens.accentInk)
                }
            }
            Routes05SectionHeader("Стан сесії") {}.padding(.horizontal, 16).padding(.top, 24)
            Routes05StateRow(text: "Готовий до запуску · мікрофон не використовується", tint: Routes05Tokens.mint).padding(.horizontal, 16)
        }
    }

    private var familyChat: some View {
        VStack(alignment: .leading, spacing: 0) {
            Routes05Chapter("SYSTEM / 18", title: "Родинний чат", detail: "Повідомлення лише в межах авторизованого профілю.", accent: Routes05Tokens.mint)
            message("Віталій", "Перевіримо спільний маршрут на завтра?", tint: Routes05Tokens.mint)
            message("Ви", "Так, після школи повернемося до цього.", tint: Routes05Tokens.lilac)
            Spacer(minLength: 160)
            HStack(spacing: 8) { TextField("Написати сім’ї…", text: $draft).textFieldStyle(.roundedBorder); Button { draft = "" } label: { Image(systemName: "arrow.up") }.buttonStyle(.borderedProminent) }.padding(16)
        }
    }

    private func message(_ sender: String, _ text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) { Circle().fill(tint).frame(width: 32, height: 32).overlay(Circle().stroke(Routes05Tokens.ink, lineWidth: 1)); VStack(alignment: .leading, spacing: 3) { Text(sender).font(.caption.weight(.black)); Text(text).font(.body) }; Spacer() }.padding(14).background(Routes05Tokens.surface).overlay(alignment: .bottom) { Rectangle().fill(Routes05Tokens.rule).frame(height: 1) }.padding(.horizontal, 16)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 0) {
            Routes05Chapter("SYSTEM / 19", title: "Налаштування", detail: "Приватність, голос і вигляд застосунку на цьому пристрої.", accent: Routes05Tokens.yellow)
            settingRow("Акаунт і профіль", "Пристрій, доступ, приватність", Routes05Tokens.mint)
            settingRow("Зовнішній вигляд", "Світла / темна / системна", Routes05Tokens.lilac)
            settingRow("Голос і мікрофон", "LiveKit та звук", Routes05Tokens.orange)
            settingRow("Підключення", "Календарі, інструменти", Routes05Tokens.yellow)
            settingRow("Admin", "Лише для власника", Routes05Tokens.mint)
            Routes05SourcePanel { VStack(alignment: .leading, spacing: 8) { Text("ДЕМО ТЕМИ").font(.headline.weight(.black)); Text("Змінюйте тему через системні налаштування або профіль.").font(.subheadline); Button("◐ Змінити тему") {}.frame(maxWidth: .infinity).padding(12).background(Routes05Tokens.yellow).foregroundStyle(Routes05Tokens.accentInk) } }.padding(.horizontal, 16).padding(.top, 22)
        }
    }

    private func settingRow(_ title: String, _ detail: String, _ tint: Color) -> some View {
        HStack(spacing: 12) { Circle().fill(tint).frame(width: 48, height: 48).overlay(Image(systemName: "circle").font(.title3).foregroundStyle(Routes05Tokens.accentInk)).overlay(Circle().stroke(Routes05Tokens.ink, lineWidth: 1.5)); VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline.weight(.black)); Text(detail).font(.subheadline).foregroundStyle(Routes05Tokens.secondary) }; Spacer(); Image(systemName: "arrow.up.right").font(.headline.weight(.black)) }.padding(.horizontal, 16).padding(.vertical, 12).overlay(alignment: .bottom) { Rectangle().fill(Routes05Tokens.rule).frame(height: 1) }.foregroundStyle(Routes05Tokens.ink)
    }

    private var integrations: some View {
        VStack(alignment: .leading, spacing: 0) {
            Routes05Chapter("SYSTEM / 20", title: "Інтеграції", detail: "Стан сервісів і безпечні точки входу Orbit.", accent: Routes05Tokens.yellow)
            Routes05FilledTile(title: "Календар", detail: "Зовнішній стан · перевірити", icon: "calendar", tint: Routes05Tokens.yellow) {}
            Routes05FilledTile(title: "Школа", detail: "Schulmanager · read only", icon: "graduationcap", tint: Routes05Tokens.mint) {}
            Routes05FilledTile(title: "Повідомлення", detail: "Доступ визначається сервером", icon: "message", tint: Routes05Tokens.lilac) {}
            Routes05StateRow(text: "Інтеграції не змінюють дані без підтвердження.", tint: Routes05Tokens.orange).padding(16)
        }
    }

    private var memoryDetail: some View { detailScreen(eyebrow: "MEMORY / FACT", title: "Факт пам’яті", detail: "Точне джерело, власник і часовий стан факту.", accent: Routes05Tokens.lilac, rows: [("Значення", "Чай з м’ятою"), ("Статус", "Актуальне"), ("Джерело", "Підтвердження профілю")]) }
    private var contactDetail: some View { detailScreen(eyebrow: "CONTACT / IDENTITY", title: "Контакт", detail: "Окрема ідентичність із дозволеними каналами.", accent: Routes05Tokens.mint, rows: [("Ім’я", "Анна · близькі"), ("Канал", "WhatsApp"), ("Доступ", "Явно дозволений")]) }

    private func detailScreen(eyebrow: String, title: String, detail: String, accent: Color, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) { Routes05Chapter(eyebrow, title: title, detail: detail, accent: accent); ForEach(Array(rows.enumerated()), id: \.offset) { _, row in Routes05SourcePanel(tint: accent) { VStack(alignment: .leading, spacing: 4) { Text(row.0).font(.caption.weight(.black)); Text(row.1).font(.headline.weight(.black)) } }.padding(.horizontal, 16).padding(.top, 10) }; darkAction("ЗАКРИТИ", detail: "←") {}.padding(16) }
    }

    private var actionConfirm: some View {
        VStack(alignment: .leading, spacing: 0) { Routes05Chapter("SYSTEM / 23", title: "Підтвердження\nдії", detail: "Наслідки показані до виконання canonical tool.", accent: Routes05Tokens.orange); Routes05Hero(accent: Routes05Tokens.orange) { VStack(alignment: .leading, spacing: 10) { Text("ПІДТВЕРДІТЬ ДІЮ").font(.caption.weight(.black)); Text("Додати подію до сімейного календаря?").font(.title2.weight(.black)); Text("Orbit ще нічого не змінив.").font(.subheadline) } }.padding(.top, 18); HStack { Button("Скасувати") { confirmed = false }.buttonStyle(.bordered); Spacer(); Button(confirmed ? "Підтверджено" : "Підтвердити") { confirmed = true }.buttonStyle(.borderedProminent).tint(Routes05Tokens.ink) }.padding(16) }
    }

    private var admin: some View { VStack(alignment: .leading, spacing: 0) { Routes05Chapter("SYSTEM / 24", title: "Admin", detail: "Read-only operational overview; actions remain guarded.", accent: Routes05Tokens.mint); Routes05StateRow(text: "Сервер: стан недоступний без авторизованого runtime", tint: Routes05Tokens.mint).padding(16); settingRow("Health", "Без production mutation", Routes05Tokens.yellow); settingRow("Backup", "Restore identity required", Routes05Tokens.lilac) } }
    private var notifications: some View { VStack(alignment: .leading, spacing: 0) { Routes05Chapter("DISCOVERY / 30", title: "Сповіщення", detail: "Шкільні й системні події для цього профілю.", accent: Routes05Tokens.yellow); notification("Нове повідомлення зі школи", "Оригінал доступний для читання", Routes05Tokens.yellow); notification("Сімейна дія очікує", "Потрібне підтвердження", Routes05Tokens.orange); notification("Голос готовий", "LiveKit не запущено", Routes05Tokens.mint) } }
    private func notification(_ title: String, _ detail: String, _ tint: Color) -> some View { Routes05Ticket(tint: tint) { VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline.weight(.black)); Text(detail).font(.subheadline).foregroundStyle(Routes05Tokens.secondary) } }.padding(.horizontal, 16) }
    private var memoryImports: some View { VStack(alignment: .leading, spacing: 0) { Routes05Chapter("DISCOVERY / 31", title: "Імпорти\nпам’яті", detail: "Перевірка перед збереженням у приватну пам’ять.", accent: Routes05Tokens.lilac); Routes05FilledTile(title: "ChatGPT export", detail: "Потрібен аналіз і підтвердження", icon: "arrow.down.doc", tint: Routes05Tokens.lilac) {}; Routes05FilledTile(title: "Інший файл", detail: "Стан імпорту перевіряється сервером", icon: "doc", tint: Routes05Tokens.mint) {}; Routes05StateRow(text: "Нічого не імпортовано автоматично.", tint: Routes05Tokens.lilac).padding(16) } }

    private func searchField(_ placeholder: String) -> some View { HStack { Image(systemName: "magnifyingglass"); TextField(placeholder, text: $query) }.padding(14).background(Routes05Tokens.surface).overlay(RoundedRectangle(cornerRadius: 4).stroke(Routes05Tokens.ink, lineWidth: 1.5)).padding(.horizontal, 16).padding(.top, 10) }
    private func filterPills(_ values: [String]) -> some View { ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { ForEach(values, id: \.self) { value in Button(value) { selectedFilter = value }.font(.subheadline.weight(.black)).foregroundStyle(selectedFilter == value ? Routes05Tokens.darkSurfaceInk : Routes05Tokens.ink).padding(.horizontal, 14).frame(minHeight: 36).background(selectedFilter == value ? Routes05Tokens.darkSurface : Routes05Tokens.surface, in: Capsule()).overlay(Capsule().stroke(Routes05Tokens.rule, lineWidth: 1.5)) } }.padding(.horizontal, 16).padding(.top, 14) } }
    private func darkAction(_ title: String, detail: String, _ action: @escaping () -> Void) -> some View { Button(action: action) { HStack { Text(title).font(.headline.weight(.black)); Text(detail).font(.subheadline); Spacer(); Image(systemName: "arrow.up.right") }.foregroundStyle(Routes05Tokens.darkSurfaceInk).padding(16).frame(maxWidth: .infinity).background(Routes05Tokens.darkSurface) }.buttonStyle(.plain).padding(.horizontal, 16) }
}
