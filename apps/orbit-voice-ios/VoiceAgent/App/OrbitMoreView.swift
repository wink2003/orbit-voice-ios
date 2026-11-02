import SwiftUI

/// The authenticated More landing screen. It owns only navigation; feature
/// stores and destination views remain in their existing screens.
struct OrbitMoreView: View {
    @EnvironmentObject private var authentication: OrbitAuthentication
    @State private var selectedTarget: OrbitAuthentication.ImpersonationTarget?
    @State private var impersonationTargets: [OrbitAuthentication.ImpersonationTarget] = []
    @State private var showingTargetPicker = false
    @State private var loadingTargets = false
    @State private var targetsError: String?
    @State private var testingPassword = ""
    @State private var testingError: String?

    private let columns = [
        GridItem(.flexible(), spacing: OrbitSpacing.medium),
        GridItem(.flexible(), spacing: OrbitSpacing.medium)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: OrbitSpacing.large) {
                    header
                    profileCard
                    quickAccess
                    management
                    secondaryFunctions
                    helpAndInformation
                    footer
                }
                .padding(.horizontal, OrbitSpacing.large)
                .padding(.top, OrbitSpacing.medium)
                .padding(.bottom, OrbitSpacing.xLarge)
            }
            .background(Routes05Tokens.canvas.ignoresSafeArea())
            .foregroundStyle(Routes05Tokens.ink)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("orbit.more")
            .sheet(item: $selectedTarget) { target in
                impersonationForm(for: target)
            }
            .sheet(isPresented: $showingTargetPicker) {
                impersonationTargetPicker
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ORBIT / НАВІГАЦІЯ")
                .font(.caption.weight(.black))
                .tracking(1.2)
                .foregroundStyle(Routes05Tokens.secondary)
            Text("Інше")
                .font(.system(.largeTitle, design: .rounded).weight(.black))
                .tracking(-1.4)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var profileCard: some View {
        NavigationLink { OrbitSettingsView() } label: {
            HStack(spacing: OrbitSpacing.medium) {
                Text(initials)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Routes05Tokens.accentInk)
                    .frame(width: 48, height: 48)
                    .background(Routes05Tokens.mint, in: Circle())
                    .overlay(Circle().stroke(Routes05Tokens.ink, lineWidth: 1.5))

                VStack(alignment: .leading, spacing: 3) {
                    Text(authentication.displayName ?? "Активний профіль")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Routes05Tokens.ink)
                    Text(authentication.hasAccountSession ? "Профіль Orbit · акаунт підключено" : "Профіль Orbit · цей iPhone")
                        .font(.footnote)
                        .foregroundStyle(Routes05Tokens.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Routes05Tokens.secondary)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: OrbitRadius.card))
            .overlay(RoundedRectangle(cornerRadius: OrbitRadius.card).stroke(Routes05Tokens.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Профіль у налаштуваннях: \(authentication.displayName ?? "активний профіль")")
        .accessibilityHint("Відкрити профіль, акаунт і захист")
        .frame(minHeight: 76)
    }

    private var quickAccess: some View {
        section(title: "Швидкий доступ") {
            LazyVGrid(columns: columns, spacing: OrbitSpacing.medium) {
                quickLink(.calendar, icon: "calendar", tint: Routes05Tokens.lilac)
                quickLink(.family, icon: "person.3.fill", tint: Routes05Tokens.mint)
                quickLink(.contacts, icon: "person.2.fill", tint: Routes05Tokens.yellow)
                quickLink(.integrations, icon: "point.3.connected.trianglepath.dotted", tint: Routes05Tokens.blue)
            }
        }
    }

    private var management: some View {
        section(title: "Керування") {
            VStack(spacing: 0) {
                if authentication.canViewServerOverview {
                    destinationRow(.admin, icon: "server.rack", detail: "Огляд сервера")
                    divider
                }
                destinationRow(.settings, icon: "gearshape", detail: "Профіль, акаунт і захист")
            }
            .background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: OrbitRadius.card))
            .overlay(RoundedRectangle(cornerRadius: OrbitRadius.card).stroke(Routes05Tokens.rule, lineWidth: 1))
        }
    }

    private var helpAndInformation: some View {
        section(title: "Допомога та інформація") {
            unavailableRow
                .background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: OrbitRadius.card))
                .overlay(RoundedRectangle(cornerRadius: OrbitRadius.card).stroke(Routes05Tokens.rule, lineWidth: 1))
        }
    }

    private var secondaryFunctions: some View {
        section(title: "Додатково") {
            VStack(spacing: 0) {
                destinationRow(.memory, icon: "brain.head.profile", detail: "Особисті та спільні факти")
                divider
                destinationRow(.calendarSettings, icon: "calendar.badge.clock", detail: "Підключення та джерела календаря")

                if authentication.impersonating {
                    divider
                    Label("Тестовий профіль: \(authentication.displayName ?? "активний")", systemImage: "person.crop.circle.badge.exclamationmark")
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 14)
                        .accessibilityElement(children: .combine)
                    Button("Вийти з тестового профілю") {
                        Task { try? await authentication.endImpersonation() }
                    }
                    .frame(maxWidth: .infinity, minHeight: OrbitSpacing.minTarget, alignment: .leading)
                    .padding(.horizontal, 14)
                }

                if authentication.principalPersonId == "oleksandr" && !authentication.impersonating {
                    divider
                    Button {
                        Task { await loadImpersonationTargets() }
                    } label: {
                        Label("Тестове перемикання профілю", systemImage: "person.crop.circle.badge.questionmark")
                            .frame(maxWidth: .infinity, minHeight: OrbitSpacing.minTarget, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                }
                if let targetsError {
                    Text(targetsError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                } else if loadingTargets {
                    ProgressView("Завантаження тестових профілів…")
                        .frame(maxWidth: .infinity, minHeight: OrbitSpacing.minTarget, alignment: .leading)
                        .padding(.horizontal, 14)
                }
                if KeychainStore.readSessionToken() != nil {
                    divider
                    Button("Вийти з акаунта Orbit", role: .destructive) {
                        Task { await authentication.logout() }
                    }
                    .frame(maxWidth: .infinity, minHeight: OrbitSpacing.minTarget, alignment: .leading)
                    .padding(.horizontal, 14)
                }
            }
            .background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: OrbitRadius.card))
            .overlay(RoundedRectangle(cornerRadius: OrbitRadius.card).stroke(Routes05Tokens.rule, lineWidth: 1))
        }
    }

    private var unavailableRow: some View {
        HStack(spacing: OrbitSpacing.medium) {
            Image(systemName: "questionmark.circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(Routes05Tokens.secondary)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Допомога та інформація")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Routes05Tokens.ink)
                Text("Довідка ще не підключена в цій збірці")
                    .font(.footnote)
                    .foregroundStyle(Routes05Tokens.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text("Недоступно")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Routes05Tokens.secondary)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Допомога та інформація. Наразі недоступно")
    }

    private var footer: some View {
        Text("Orbit Family AI · Main Orbit")
            .font(.caption)
            .foregroundStyle(Routes05Tokens.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, OrbitSpacing.small)
            .accessibilityLabel("Orbit Family AI, Main Orbit")
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.medium) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(Routes05Tokens.ink)
            content()
        }
    }

    private func quickLink(_ destination: OrbitMoreDestination, icon: String, tint: Color) -> some View {
        NavigationLink { screen(for: destination) } label: {
            VStack(alignment: .leading, spacing: OrbitSpacing.medium) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Routes05Tokens.accentInk)
                    .frame(width: 36, height: 36)
                    .background(tint, in: RoundedRectangle(cornerRadius: OrbitRadius.chip))
                Text(destination.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Routes05Tokens.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: OrbitRadius.card))
            .overlay(RoundedRectangle(cornerRadius: OrbitRadius.card).stroke(Routes05Tokens.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(destination.title)
        .accessibilityHint("Відкрити розділ")
    }

    private func destinationRow(_ destination: OrbitMoreDestination, icon: String, detail: String) -> some View {
        NavigationLink { screen(for: destination) } label: {
            HStack(spacing: OrbitSpacing.medium) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Routes05Tokens.accentInk)
                    .frame(width: 34, height: 34)
                    .background(Routes05Tokens.yellow, in: RoundedRectangle(cornerRadius: OrbitRadius.chip))
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Routes05Tokens.ink)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Routes05Tokens.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .foregroundStyle(Routes05Tokens.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, OrbitSpacing.large)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(destination.title)
        .accessibilityHint("Відкрити розділ")
    }

    private var divider: some View {
        Rectangle()
            .fill(Routes05Tokens.rule)
            .frame(height: 1)
            .padding(.leading, 64)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func screen(for destination: OrbitMoreDestination) -> some View {
        switch destination {
        case .calendar: OrbitCalendarView()
        case .family: FamilyHubView()
        case .contacts: OrbitContactsView()
        case .integrations: OrbitToolsView()
        case .admin: OrbitDashboardView(isSelected: true)
        case .settings: OrbitSettingsView()
        case .memory: MemoryCenterView()
        case .calendarSettings: CalendarSettingsView()
        }
    }

    private func loadImpersonationTargets() async {
        loadingTargets = true
        targetsError = nil
        defer { loadingTargets = false }
        do {
            let targets = try await authentication.impersonationTargets()
            let allowedIDs = OrbitTargetFiltering.selectableTargetIds(
                targets.map(\.personId),
                principalPersonId: authentication.principalPersonId
            )
            impersonationTargets = targets.filter { allowedIDs.contains($0.personId) }
            showingTargetPicker = true
        } catch {
            targetsError = error.localizedDescription
        }
    }

    private func impersonationForm(for target: OrbitAuthentication.ImpersonationTarget) -> some View {
        NavigationStack {
            Form {
                Section("Тестовий профіль") { Text(target.displayName) }
                SecureField("Пароль власника", text: $testingPassword)
                if let testingError { Text(testingError).foregroundStyle(.red) }
                Button("Увімкнути на 15 хвилин") {
                    Task {
                        do {
                            try await authentication.beginImpersonation(targetPersonId: target.personId, password: testingPassword)
                            selectedTarget = nil
                            testingPassword = ""
                            testingError = nil
                        } catch {
                            testingError = error.localizedDescription
                        }
                    }
                }
                .disabled(testingPassword.isEmpty)
            }
            .navigationTitle("Тестовий режим")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { selectedTarget = nil } } }
        }
    }

    private var impersonationTargetPicker: some View {
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
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { showingTargetPicker = false } } }
        }
    }

    private var initials: String {
        let parts = (authentication.displayName ?? "Orbit").split(separator: " ")
        return String(parts.prefix(2).compactMap { $0.first }).uppercased()
    }
}
