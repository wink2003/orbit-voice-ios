import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var authentication: OrbitAuthentication
    @State private var code = ""
    @State private var isPairing = false
    @State private var errorMessage: String?
    @State private var loginMode = false
    @State private var login = ""
    @State private var password = ""

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.02, green: 0.08, blue: 0.09), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Text("ORBIT")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .tracking(8)
                    .foregroundStyle(Color(red: 0.45, green: 0.9, blue: 0.8))

                Circle()
                    .fill(Color(red: 0.2, green: 0.85, blue: 0.7))
                    .frame(width: 150, height: 150)
                    .shadow(color: Color(red: 0.2, green: 0.9, blue: 0.75).opacity(0.5), radius: 35)

                VStack(spacing: 10) {
                    Text(loginMode ? "Вхід до Main Orbit" : "Активація iPhone")
                        .font(.title2.bold())
                    Text(loginMode ? "Увійдіть за логіном і паролем Main Orbit." : "Введіть одноразовий код, який створив Orbit.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if loginMode {
                    TextField("Логін", text: $login).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username).padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    SecureField("Пароль", text: $password).textContentType(.password).padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                } else {
                    TextField("000000", text: $code)
                        .keyboardType(.numberPad).textContentType(.oneTimeCode)
                        .font(.system(size: 30, weight: .semibold, design: .monospaced)).multilineTextAlignment(.center).padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                        .onChange(of: code) { _, value in code = String(value.filter(\.isNumber).prefix(6)) }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await pair() }
                } label: {
                    Group {
                        if isPairing { ProgressView() } else { Text(loginMode ? "Увійти в Orbit" : "Активувати Orbit") }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.2, green: 0.85, blue: 0.7))
                .foregroundStyle(.black)
                .disabled((loginMode ? (login.isEmpty || password.isEmpty) : code.count != 6) || isPairing)

                Button(loginMode ? "Використати одноразовий код" : "Увійти за логіном") {
                    loginMode.toggle(); errorMessage = nil
                }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(28)
        }
        .preferredColorScheme(.dark)
    }

    private func pair() async {
        isPairing = true
        errorMessage = nil
        defer { isPairing = false }
        do {
            if loginMode { try await authentication.login(login: login, password: password) }
            else { try await authentication.pair(code: code) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
