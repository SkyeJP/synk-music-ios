import Foundation
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    enum State: Equatable {
        case loading
        case loggedOut
        case loggedIn(User)
    }

    @Published var state: State = .loading

    var user: User? {
        if case let .loggedIn(u) = state { return u }
        return nil
    }

    // On launch: if we hold a token, validate it via /auth/me.
    func restore() async {
        guard let token = AuthStore.shared.token, !token.isEmpty else {
            state = .loggedOut
            return
        }
        do {
            let me = try await API.shared.me()
            if let user = me.user {
                state = .loggedIn(user)
            } else {
                state = .loggedOut
            }
        } catch {
            state = .loggedOut
        }
    }

    func login(email: String, password: String) async throws {
        let resp = try await API.shared.login(email, password)
        AuthStore.shared.token = resp.token
        if let user = resp.user {
            state = .loggedIn(user)
        } else {
            await restore()
        }
    }

    func verify(email: String, code: String) async throws {
        let resp = try await API.shared.verify(email, code)
        AuthStore.shared.token = resp.token
        if let user = resp.user { state = .loggedIn(user) } else { await restore() }
    }

    func register(email: String, username: String, password: String) async throws {
        _ = try await API.shared.register(email, username, password)
    }

    func logout() {
        AuthStore.shared.token = nil
        PlayerController.shared.stop()
        state = .loggedOut
    }
}
