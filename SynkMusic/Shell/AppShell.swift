import SwiftUI

enum Tab: Int, CaseIterable {
    case home, search, library, analytics, profile

    var title: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .library: return "Library"
        case .analytics: return "Stats"
        case .profile: return "Profile"
        }
    }
    var icon: SynkVector {
        switch self {
        case .home: return SynkIcons.home
        case .search: return SynkIcons.search
        case .library: return SynkIcons.library
        case .analytics: return SynkIcons.chart
        case .profile: return SynkIcons.user
        }
    }
}

struct AppShell: View {
    @State private var tab: Tab = .home
    @State private var showPlayer = false
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.ink.ignoresSafeArea()

            Group {
                switch tab {
                case .home: NavigationStack { HomeView().withRoutes() }
                case .search: NavigationStack { SearchView().withRoutes() }
                case .library: NavigationStack { LibraryView().withRoutes() }
                case .analytics: NavigationStack { AnalyticsView().withRoutes() }
                case .profile: NavigationStack { ProfileView().withRoutes() }
                }
            }
            .padding(.bottom, player.current != nil ? 116 : 56)

            VStack(spacing: 0) {
                if player.current != nil {
                    MiniPlayer { showPlayer = true }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                TabBar(selected: $tab)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: player.current)
        .fullScreenCover(isPresented: $showPlayer) {
            FullPlayer(onClose: { showPlayer = false })
        }
        .onAppear {
            LikesStore.shared.refresh()
        }
    }
}

struct TabBar: View {
    @Binding var selected: Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.rawValue) { tab in
                Button { selected = tab } label: {
                    VStack(spacing: 4) {
                        SynkIcon(vector: tab.icon, size: 24,
                                 tint: selected == tab ? Theme.fg : Theme.faint)
                        Text(tab.title)
                            .font(SynkFont.sans(10, .medium))
                            .foregroundStyle(selected == tab ? Theme.fg : Theme.faint)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(Theme.base.opacity(0.98))
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(Theme.line), alignment: .top)
    }
}
