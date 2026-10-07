import SwiftUI

struct OrbitMoreView: View {
    @EnvironmentObject private var authentication: OrbitAuthentication
    @State private var selectedTarget: OrbitAuthentication.ImpersonationTarget?
    @State private var impersonationTargets: [OrbitAuthentication.ImpersonationTarget] = []
    @State private var showingTargetPicker = false
    @State private var loadingTargets = false
    @State private var targetsError: String?
    @State private var testingPassword = ""
    @State private var testingError: String?

    var body: some View {
        NavigationStack {
            List {
                if authentication.impersonating {
                    Section {
                        Label("Тестовий профіль: \(authentication.displayName ?? "активний")", systemImage: "person.crop.circle.badge.exclamationmark")
                            .foregroundStyle(.orange)
                        Button("Вийти з тестового профілю") {
                            Task { try? await authentication.endImpersonation() }
                        }
                    }
                }
                Section {
                    Label(authentication.displayName ?? "Активний профіль", systemImage: "person.crop.circle")
                        .font(.headline)
                        .frame(minHeight: OrbitSpacing.minTarget)
                        .accessibilityLabel("Профіль: \(authentication.displayName ?? "активний профіль")")
                }
                Section {
                    ForEach(OrbitNavigation.moreDestinations(isOwner: authentication.canViewServerOverview)) { destination in
                        NavigationLink { screen(for: destination) } label: { row(for: destination) }
                            .frame(minHeight: OrbitSpacing.minTarget)
                    }
                }
                Section("Календарі") {
                    NavigationLink { CalendarSettingsView() } label: { Label("Підключення календарів", systemImage: "calendar.badge.clock") }
                }
                Section {
                    if authentication.principalPersonId == "oleksandr" && !authentication.impersonating {
                        Button("Тестове перемикання профілю") {
                            Task {
                                loadingTargets = true
                                targetsError = nil
                                defer { loadingTargets = false }
                                do {
                                    let targets = try await authentication.impersonationTargets()
                                    let allowedIds = OrbitTargetFiltering.selectableTargetIds(
                                        targets.map(\.personId),
                                        principalPersonId: authentication.principalPersonId
                                    )
                                    impersonationTargets = targets.filter { allowedIds.contains($0.personId) }
                                    showingTargetPicker = true
                                } catch {
                                    targetsError = error.localizedDescription
                                }
                            }
                        }
                    }
                    if let targetsError {
                        Text(targetsError).font(.footnote).foregroundStyle(.red)
                    } else if loadingTargets {
                        ProgressView("Завантаження тестових профілів…")
                    }
                    if KeychainStore.readSessionToken() != nil {
                        Button("Вийти з акаунта Orbit", role: .destructive) { Task { await authentication.logout() } }
                    }
                    Text("Main Orbit — сімейний AI-помічник. Orbit Mini залишається окремим клієнтом для голосу без рук.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ще")
            .sheet(item: $selectedTarget) { target in
                NavigationStack {
                    Form {
                        Section("Тестовий профіль") { Text(target.displayName) }
                        SecureField("Пароль власника", text: $testingPassword)
                        if let testingError { Text(testingError).foregroundStyle(.red) }
                        Button("Увімкнути на 15 хвилин") {
                            Task {
                                do { try await authentication.beginImpersonation(targetPersonId: target.personId, password: testingPassword); selectedTarget = nil; testingPassword = ""; testingError = nil }
                                catch { testingError = error.localizedDescription }
                            }
                        }.disabled(testingPassword.isEmpty)
                    }
                    .navigationTitle("Тестовий режим")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { selectedTarget = nil } } }
                }
            }
            .sheet(isPresented: $showingTargetPicker) {
                NavigationStack {
                    List {
                        if impersonationTargets.isEmpty {
                            ContentUnavailableView("Профілів немає", systemImage: "person.crop.circle.badge.xmark", description: Text("Сервер не надав доступних профілів для тестування."))
                        } else {
                            Section("Оберіть профіль") {
                                ForEach(impersonationTargets) { target in
                                    Button {
                                        selectedTarget = target
                                        showingTargetPicker = false
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(target.displayName).foregroundStyle(.primary)
                                            Text(target.isMinor ? "Дитина" : "Член родини")
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(minHeight: OrbitSpacing.minTarget)
                                }
                            }
                        }
                    }
                    .navigationTitle("Тестовий профіль")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Скасувати") { showingTargetPicker = false }
                        }
                    }
                }
            }
        }
    }


    @ViewBuilder private func screen(for destination: OrbitMoreDestination) -> some View {
        switch destination {
        case .memory: MemoryCenterView()
        case .family: FamilyHubView()
        case .contacts: OrbitContactsView()
        case .settings: OrbitSettingsView()
        case .admin: OrbitDashboardView(isSelected: true)
        }
    }

    @ViewBuilder private func row(for destination: OrbitMoreDestination) -> some View {
        switch destination {
        case .memory: Label("Пам’ять", systemImage: "brain.head.profile")
        case .family: Label("Сім’я", systemImage: "person.3")
        case .contacts: Label("Контакти", systemImage: "person.crop.circle.badge.plus")
        case .settings: Label("Налаштування", systemImage: "gearshape")
        case .admin: Label("Admin · сервер", systemImage: "server.rack")
        }
    }
}
