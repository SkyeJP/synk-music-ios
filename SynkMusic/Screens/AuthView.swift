import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var session: SessionStore

    enum Mode { case login, register, verify }
    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var code = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Spacer(minLength: 60)

                    Image("SynkLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    Text("SYNK Music")
                        .font(SynkFont.sans(26, .heavy))
                        .foregroundStyle(Theme.fg)
                    Text(subtitle)
                        .font(SynkFont.sans(14))
                        .foregroundStyle(Theme.muted)
                        .padding(.bottom, 8)

                    switch mode {
                    case .login:
                        field("Email", text: $email, keyboard: .emailAddress)
                        secureField("Password", text: $password)
                        primaryButton("Log in") { await doLogin() }
                        switcher("Don't have an account?", "Sign up") { mode = .register; error = nil }
                    case .register:
                        field("Email", text: $email, keyboard: .emailAddress)
                        field("Username", text: $username)
                        secureField("Password", text: $password)
                        primaryButton("Create account") { await doRegister() }
                        switcher("Already have an account?", "Log in") { mode = .login; error = nil }
                    case .verify:
                        Text("Enter the code sent to \(email)")
                            .font(SynkFont.sans(13)).foregroundStyle(Theme.muted)
                        field("Verification code", text: $code, keyboard: .numberPad)
                        primaryButton("Verify") { await doVerify() }
                    }

                    if let error = error {
                        Text(error).font(SynkFont.sans(13)).foregroundStyle(.red)
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 28)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var subtitle: String {
        switch mode {
        case .login: return "Welcome back"
        case .register: return "Create your account"
        case .verify: return "Confirm your email"
        }
    }

    private func field(_ prompt: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        TextField("", text: text, prompt: Text(prompt).foregroundColor(Theme.faint))
            .font(SynkFont.sans(15))
            .foregroundStyle(Theme.fg)
            .keyboardType(keyboard)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 14).padding(.vertical, 14)
            .background(Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func secureField(_ prompt: String, text: Binding<String>) -> some View {
        SecureField("", text: text, prompt: Text(prompt).foregroundColor(Theme.faint))
            .font(SynkFont.sans(15))
            .foregroundStyle(Theme.fg)
            .padding(.horizontal, 14).padding(.vertical, 14)
            .background(Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func primaryButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { busy = true; await action(); busy = false }
        } label: {
            ZStack {
                if busy { ProgressView().tint(Theme.ink) }
                else { Text(title).font(SynkFont.sans(15, .semibold)).foregroundStyle(Theme.ink) }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(Theme.fg)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .padding(.top, 4)
    }

    private func switcher(_ text: String, _ action: String, tap: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(text).font(SynkFont.sans(13)).foregroundStyle(Theme.muted)
            Button(action: tap) {
                Text(action).font(SynkFont.sans(13, .semibold)).foregroundStyle(Theme.fg)
            }
        }
        .padding(.top, 4)
    }

    private func doLogin() async {
        error = nil
        do { try await session.login(email: email, password: password) }
        catch { self.error = "Invalid email or password" }
    }
    private func doRegister() async {
        error = nil
        do { try await session.register(email: email, username: username, password: password); mode = .verify }
        catch { self.error = "Couldn't create account" }
    }
    private func doVerify() async {
        error = nil
        do { try await session.verify(email: email, code: code) }
        catch { self.error = "Invalid code" }
    }
}
