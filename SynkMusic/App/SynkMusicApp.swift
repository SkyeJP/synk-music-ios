import SwiftUI
import UIKit

@MainActor
final class SessionStore: ObservableObject {
    enum Phase { case loading, loggedOut, loggedIn }

    @Published private(set) var state: Phase = .loading
    @Published private(set) var user: User?
    @Published var busy = false
    @Published var error: String?
    @Published var needsVerification = false
    private var pendingEmail = ""

    init() {
        NotificationCenter.default.addObserver(forName: .synkSessionExpired, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .loggedIn else { return }
                self.tearDown()
                AuthStore.shared.user = nil
                self.user = nil
                self.state = .loggedOut
                self.error = "Your session has expired, please sign in again"
            }
        }
    }

    func restore() async {
        guard let t = AuthStore.shared.token, !t.isEmpty else { state = .loggedOut; return }
        user = AuthStore.shared.user
        if let fresh = try? await withTimeout(3, { try await API.shared.me() }) {
            AuthStore.shared.user = fresh
            user = fresh
        }
        let hasToken = !(AuthStore.shared.token ?? "").isEmpty
        state = (user != nil && hasToken) ? .loggedIn : .loggedOut
        if state == .loggedIn { DeviceTuningManager.shared.refresh() }
    }

    func login(_ email: String, _ password: String) {
        run {
            let (token, user) = try await API.shared.login(email.trimmingCharacters(in: .whitespaces), password)
            try self.signedIn(token, user)
        }
    }

    func register(_ email: String, _ username: String, _ password: String, invite: String) {
        run {
            try await API.shared.register(email.trimmingCharacters(in: .whitespaces), username.trimmingCharacters(in: .whitespaces),
                                          password, invite: invite.trimmingCharacters(in: .whitespaces))
            self.pendingEmail = email.trimmingCharacters(in: .whitespaces)
            self.needsVerification = true
        }
    }

    func verify(_ code: String) {
        run {
            let (token, user) = try await API.shared.verify(self.pendingEmail, code.trimmingCharacters(in: .whitespaces))
            try self.signedIn(token, user)
        }
    }

    func logout() {
        tearDown()
        Task { await API.shared.logout() }
        AuthStore.shared.token = nil
        AuthStore.shared.user = nil
        user = nil
        state = .loggedOut
    }

    private func signedIn(_ token: String, _ user: User?) throws {
        guard let user, !token.isEmpty else { throw APIError(status: 0, message: "No user returned") }
        AuthStore.shared.token = token
        AuthStore.shared.user = user
        self.user = user
        needsVerification = false
        state = .loggedIn
        LikesStore.shared.refresh()
        DeviceTuningManager.shared.refresh()
    }

    private func tearDown() {
        LtClient.shared.end()
        CdcClient.shared.disconnect()
        PlayerController.shared.stop()
    }

    private func run(_ work: @MainActor @escaping () async throws -> Void) {
        busy = true
        error = nil
        Task {
            do { try await work() } catch { self.error = (error as? APIError)?.message ?? API.friendly(0) }
            busy = false
        }
    }
}

private func withTimeout<T: Sendable>(_ seconds: Double, _ op: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { g in
        g.addTask { try await op() }
        g.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw CancellationError()
        }
        let first = try await g.next()!
        g.cancelAll()
        return first
    }
}

@main
struct SynkMusicApp: App {
    @StateObject private var session = SessionStore()

    init() {
        SynkFont.register()
        // Brand fonts in the system navigation bar; its background stays the system glass.
        let nav = UINavigationBar.appearance()
        nav.largeTitleTextAttributes = [.font: SynkFont.ui("Host Grotesk", 34, 700), .foregroundColor: UIColor.white]
        nav.titleTextAttributes = [.font: SynkFont.ui("Figtree", 17, 600), .foregroundColor: UIColor.white]
        _ = SettingsStore.shared
        DeviceTuningManager.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(PlayerController.shared)
                .environmentObject(PlayerClock.shared)
                .environmentObject(CdcClient.shared)
                .environmentObject(LtClient.shared)
                .environmentObject(LikesStore.shared)
                .environmentObject(DownloadStore.shared)
                .environmentObject(SettingsStore.shared)
                .environmentObject(NetworkMonitor.shared)
                .environmentObject(LibraryModel.shared)
                .environmentObject(DeviceTuningManager.shared)
                .environmentObject(Sheets.shared)
                .preferredColorScheme(.dark)
                .tint(Theme.fg)
                .onOpenURL { url in
                    // https://synkmusic.co.uk/?lt=<id> or synk://?lt=<id>
                    let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "lt" }?.value
                    if let id, !id.isEmpty { LtClient.shared.join(id) }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            switch session.state {
            case .loading: ProgressView().tint(Theme.fg)
            case .loggedOut: AuthView()
            case .loggedIn: AppShell()
            }
        }
        .task { await session.restore() }
    }
}

struct AuthView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var register = false
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var invite = ""
    @State private var code = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Spacer().frame(height: 120)
                Text("SYNK Music").font(sans: 30, 300).foregroundStyle(Theme.fg)
                Text(session.needsVerification ? "Enter the code we emailed you" : register ? "Create your account (Invite required)" : "Welcome back")
                    .font(sans: 15).foregroundStyle(Theme.muted)
                Spacer().frame(height: 16)
                if session.needsVerification {
                    field("Verification code", $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                    primary(session.busy ? "Verifying" : "Verify") { session.verify(code) }
                } else {
                    if register { field("Invite code", $invite).textInputAutocapitalization(.characters) }
                    field("Email", $email).keyboardType(.emailAddress).textContentType(.username)
                    if register { field("Username", $username) }
                    SecureField("", text: $password, prompt: Text("Password").foregroundColor(Theme.faint))
                        .textContentType(register ? .newPassword : .password)
                        .modifier(FieldStyle())
                    Spacer().frame(height: 8)
                    primary(session.busy ? "Please wait" : register ? "Sign up" : "Log in") {
                        if register { session.register(email, username, password, invite: invite) } else { session.login(email, password) }
                    }
                    Button { register.toggle(); session.error = nil } label: {
                        Text(register ? "Have an account? Log in" : "No account? Sign up").font(sans: 14).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                if let e = session.error {
                    Text(e).font(sans: 14).foregroundStyle(Theme.danger).padding(.top, 6)
                }
            }
            .padding(.horizontal, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.ink)
    }

    private func field(_ placeholder: String, _ text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundColor(Theme.faint))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .modifier(FieldStyle())
    }

    private func primary(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(sans: 15, 600).foregroundStyle(Color.black)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(Capsule().fill(Theme.fg.opacity(session.busy ? 0.6 : 1)))
        }
        .buttonStyle(PressStyle())
        .disabled(session.busy)
    }
}

private struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(SynkFont.sans(16))
            .foregroundStyle(Theme.fg)
            .tint(Theme.fg)
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface2))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
    }
}
