import Foundation

#if DEBUG
struct Routes05ChatFixture {
    let profile: OrbitProfile
    let chats: [OrbitConversation]
}

struct Routes05SchoolFixture {
    let items: [OrbitSchoolItem]
    let events: [OrbitSchulmanagerCalendarEvent]
    let tasks: [OrbitSchoolTask]
    let studentNames: [String]
}

struct Routes05FamilyFixture {
    let profiles: [OrbitFamilyProfile]
    let messages: [OrbitFamilyMessage]
}

enum Routes05DebugScreen {
    case today, orbit, school, family
    case conversation, inbox, letter, tasks, timetable, exams, brain, calendar, search, timeline, briefing, notes, history
}

enum Routes05DebugFixtures {
    private static let now = Date(timeIntervalSince1970: 1_729_555_200)
    private static let iso: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter()
        value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return value
    }()

    static let today = NovaTodayFixture.demo

    static let chats = Routes05ChatFixture(
        profile: OrbitProfile(personId: "routes05-person", displayName: "Олена", familyId: "routes05-family", isMinor: false),
        chats: [
            OrbitConversation(id: "routes05-personal", kind: "personal", title: "Особисті", subtitle: "Ваші розмови, збережені в Orbit", lastMessage: "План на завтра", updatedAt: now),
            OrbitConversation(id: "routes05-school", kind: "school", title: "Школа", subtitle: "Окрема розмова про школу", lastMessage: "Є новий лист зі школи", updatedAt: now.addingTimeInterval(-86_400)),
            OrbitConversation(id: "routes05-family", kind: "family", title: "Родинні справи", subtitle: "Сімейна розмова · авторизована", lastMessage: "Перевіримо календар?", updatedAt: now.addingTimeInterval(-172_800))
        ]
    )

    static let conversationMessages: [OrbitChatMessage] = [
        OrbitChatMessage(id: "routes05-user-message", conversationId: "routes05-personal", senderKind: "person", senderPersonId: nil, content: "Допоможи підготувати день: школа, басейн і справи.", createdAt: now.addingTimeInterval(-900), clientMessageId: "routes05-client", actionConfirmation: nil),
        OrbitChatMessage(id: "routes05-orbit-message", conversationId: "routes05-personal", senderKind: "orbit", senderPersonId: nil, content: "Ось ваш маршрут на завтра.\n\n08:00 — Школа\nПочаток занять\n\n13:40 — Плавання\nВзяти спортивну сумку\n\n19:00 — Підготовка\nПереглянути справи", createdAt: now.addingTimeInterval(-840), clientMessageId: nil, actionConfirmation: nil)
    ]

    static let schoolBrainMessages: [OrbitSchoolBrainMessage] = [
        OrbitSchoolBrainMessage(
            id: "routes05-brain-answer",
            role: "assistant",
            content: "Цього тижня важливо підготувати матеріали до Projektwoche. Перевірте дату в оригіналі листа та підтвердіть сімейні дії окремо.",
            sourceRefs: [["id": "routes05-letter", "type": "letter"]],
            createdAt: now
        )
    ]

    static let school: Routes05SchoolFixture = {
        let letter = OrbitSchoolItem(
            id: "routes05-letter", type: "letter", source: "schulmanager", externalId: "routes05-letter",
            title: "Projektwoche", sender: "Gymnasium am Park",
            originalGerman: "Die Projektwoche findet vom 24. bis 28. Oktober statt.",
            originalPlainText: "Die Projektwoche findet vom 24. bis 28. Oktober statt.",
            previewPlainText: "Projektwoche · wichtige Informationen", titlePlainText: "Projektwoche",
            translationUkrainian: "Проєктний тиждень відбудеться з 24 до 28 жовтня.",
            important: "Перевірте лист і підготуйте необхідні матеріали.", sourceTimestamp: now,
            importedAt: now, orbitReadAt: nil, unread: true, attachments: [], events: [], threadId: nil,
            subscriptionId: nil, tasks: [OrbitSchoolItemTask(key: "prepare", title: "Підготувати матеріали", action: "Перевірити дату в джерелі", dueAt: "2026-10-24", allDay: true, importance: "normal", target: nil, confidence: 1, reason: "Source text",)]
        )
        let task = OrbitSchoolTask(key: "prepare", stableIdentity: true, title: "Підготовка до тесту", action: "Перевірити дату в джерелі", dueAt: "2026-10-24", endsAt: nil, allDay: true, importance: "high", target: nil, confidence: 1, reason: "Source text", location: nil, sourceItemId: letter.id, sourceType: "letter", sourceExternalId: letter.externalId, bucket: nil, status: "open", completedAt: nil, actionTaskId: nil, calendarEventId: nil)
        return Routes05SchoolFixture(items: [letter], events: [], tasks: [task], studentNames: ["Ліна"])
    }()

    static let family = Routes05FamilyFixture(
        profiles: [
            OrbitFamilyProfile(personId: "routes05-adult", displayName: "Олена", isMinor: false),
            OrbitFamilyProfile(personId: "routes05-partner", displayName: "Віталій", isMinor: false),
            OrbitFamilyProfile(personId: "routes05-child", displayName: "Оля", isMinor: true)
        ],
        messages: [
            OrbitFamilyMessage(id: "routes05-message", familyId: "routes05-family", senderPersonId: "routes05-partner", senderDisplayName: "Віталій", content: "Перевіримо спільний маршрут на завтра?", createdAt: now)
        ]
    )
}
#endif
