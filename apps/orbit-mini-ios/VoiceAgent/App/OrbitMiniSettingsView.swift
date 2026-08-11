import SwiftUI

struct OrbitMiniSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authentication: OrbitAuthentication
    @AppStorage("mini.continuousConversation") private var continuousConversation = true
    @AppStorage("mini.startListeningImmediately") private var startListeningImmediately = true
    @AppStorage("mini.inactivityTimeout") private var inactivityTimeout = "60"
    @AppStorage("mini.liveActivityEnabled") private var liveActivityEnabled = true
    @AppStorage("mini.liveActivityBanners") private var liveActivityBanners = true
    @AppStorage("mini.readyHaptic") private var readyHaptic = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Користувач") {
                    Picker("Користувач за замовчуванням", selection: Binding(
                        get: { authentication.personId ?? "" },
                        set: { selected in
                            guard let profile = authentication.familyProfiles.first(where: { $0.personId == selected }) else { return }
                            Task { try? await authentication.selectProfile(profile) }
                        }
                    )) {
                        ForEach(authentication.familyProfiles) { profile in
                            Text(profile.displayName).tag(profile.personId)
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
                Section("Зворотний зв’язок") {
                    Toggle("Вібрація, коли готовий", isOn: $readyHaptic)
                    Toggle("Live Activity", isOn: $liveActivityEnabled)
                    Toggle("Банер при зміні співрозмовника", isOn: $liveActivityBanners)
                }
                Section("Hands-free") {
                    Text("У «Швидких командах»: Отримати поточну програму → Start Orbit Mini → Відкрити отриману програму. Це повертає вас до Maps, Safari або іншої відкритої програми після готовності Orbit.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Налаштування")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
}
