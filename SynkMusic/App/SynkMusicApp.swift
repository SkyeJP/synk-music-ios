import SwiftUI

@main
struct SynkMusicApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var player = PlayerController.shared
    @StateObject private var likes = LikesStore.shared
    @StateObject private var downloads = DownloadStore.shared
    @StateObject private var settings = SettingsStore.shared

    init() {
        FontRegistrar.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(player)
                .environmentObject(likes)
                .environmentObject(downloads)
                .environmentObject(settings)
                .preferredColorScheme(.dark)
                .tint(Theme.fg)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            switch session.state {
            case .loading:
                ProgressView().tint(Theme.fg)
            case .loggedOut:
                AuthView()
            case .loggedIn:
                AppShell()
            }
        }
        .task { await session.restore() }
    }
}
