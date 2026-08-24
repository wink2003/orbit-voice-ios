import SwiftUI
import UIKit

struct OrbitMiniSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authentication: OrbitAuthentication
    @AppStorage("mini.continuousConversation") private var continuousConversation = true
    @AppStorage("mini.startListeningImmediately") private var startListeningImmediately = true
    @AppStorage("mini.inactivityTimeout") private var inactivityTimeout = "60"
    @AppStorage("mini.liveActivityEnabled") private var liveActivityEnabled = true
    @AppStorage(OrbitMiniLiveActivityBannerMode.storageKey) private var liveActivityBannerMode = OrbitMiniLiveActivityBannerMode.onlyOrbit.rawValue
    @AppStorage("mini.readyHaptic") private var readyHaptic = true
    @State private var endPhrases = OrbitMiniEndPhrases.phrases
    @State private var newEndPhrase = ""
    @State private var addingEndPhrase = false
    @State private var diagnosticCount = OrbitMiniDiagnosticLogger.shared.eventCount
    @State private var diagnosticCopied = false

    private var profileSelection: Binding<String> {
        Binding(
            get: { authentication.personId ?? "" },
            set: { selected in
                guard let profile = authentication.familyProfiles.first(where: { $0.personId == selected }) else { return }
                Task { try? await authentication.selectProfile(profile) }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Користувач") {
                    if authentication.familyProfiles.isEmpty {
                        Text(authentication.familyProfilesLoadState == .loading ? "Завантаження профілів…" : "Профілі недоступні")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Користувач за замовчуванням", selection: profileSelection) {
                            ForEach(authentication.familyProfiles) { profile in
                                Text(profile.displayName).tag(profile.personId)
                            }
                        }
                    }
                }
                Section("Розмова") {
                    Toggle("Безперервна розмова", isOn: $continuousConversation)
                    Toggle("Слухати одразу після старту", isOn: $startListeningImmediately)
                    Picker("Тайм-аут бездіяльності", selection: $inactivityTimeout) {
                        Text("30 секунд").tag("30")
                        Text("60 секунд").tag("60")
                        Text("120 секунд").tag("120")
                        Text("Вимкнено").tag("off")
                    }
                }
                Section {
                    ForEach(endPhrases, id: \.self) { phrase in
                        Text(phrase)
                    }
                    .onDelete { offsets in
                        endPhrases.remove(atOffsets: offsets)
                        OrbitMiniEndPhrases.save(endPhrases)
                        endPhrases = OrbitMiniEndPhrases.phrases
                    }
                    Button("Додати фразу", systemImage: "plus") {
                        newEndPhrase = ""
                        addingEndPhrase = true
                    }
                    Button("Відновити типові", role: .destructive) {
                        OrbitMiniEndPhrases.restoreDefaults()
                        endPhrases = OrbitMiniEndPhrases.phrases
                    }
                } header: {
                    Text("Фрази завершення")
                } footer: {
                    Text("Orbit завершує розмову лише якщо розпізнаний вислів точно збігається з однією з цих коротких фраз.")
                }
                Section("Зворотний зв’язок") {
                    Toggle("Вібрація, коли готовий", isOn: $readyHaptic)
                    Toggle("Live Activity", isOn: $liveActivityEnabled)
                    Picker("Банер під час розмови", selection: $liveActivityBannerMode) {
                        ForEach(OrbitMiniLiveActivityBannerMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                }
                Section {
                    HStack {
                        Text("Build")
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")
                    }
                    HStack {
                        Text("Подій збережено")
                        Spacer()
                        Text("\(diagnosticCount)")
                    }
                    Button("Скопіювати діагностику", systemImage: "doc.on.clipboard") {
                        UIPasteboard.general.string = OrbitMiniDiagnosticLogger.shared.exportText()
                        diagnosticCopied = true
                    }
                    Button("Очистити діагностику", systemImage: "trash", role: .destructive) {
                        OrbitMiniDiagnosticLogger.shared.clear()
                        diagnosticCount = 0
                        diagnosticCopied = false
                    }
                    if diagnosticCopied {
                        Text("Діагностику скопійовано")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Діагностика")
                } footer: {
                    Text("Зберігаються лише останні 300 безпечних подій Siri/audio, але не більше 384 КБ.")
                }
                Section("Hands-free") {
                    Text("Повернення до попередньої програми налаштовується зовнішньою «Швидкою командою» та персональною автоматизацією. Orbit Mini не закриває власну сцену.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Налаштування")
            .onAppear { diagnosticCount = OrbitMiniDiagnosticLogger.shared.eventCount }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .alert("Нова фраза завершення", isPresented: $addingEndPhrase) {
                TextField("Наприклад, стоп", text: $newEndPhrase)
                Button("Скасувати", role: .cancel) {}
                Button("Додати") {
                    let candidate = OrbitMiniEndPhrases.normalize(newEndPhrase)
                    guard !candidate.isEmpty else { return }
                    endPhrases.append(candidate)
                    OrbitMiniEndPhrases.save(endPhrases)
                    endPhrases = OrbitMiniEndPhrases.phrases
                }
            } message: {
                Text("Коротка команда, наприклад «досить». Порожні та повторні фрази не зберігаються.")
            }
        }
    }
}
