import SwiftUI

@MainActor
final class AnalyticsViewModel: ObservableObject {
    @Published var recent: [Track] = []
    @Published var loading = false

    func load() async {
        if !recent.isEmpty { return }
        loading = true
        defer { loading = false }
        recent = (try? await API.shared.recent())?.tracks ?? []
    }
}

struct AnalyticsView: View {
    @StateObject private var vm = AnalyticsViewModel()
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Your Stats")
                    .font(SynkFont.sans(23, .heavy))
                    .foregroundStyle(Theme.fg)
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 12)

                if let stats = session.user?.stats {
                    HStack(spacing: 10) {
                        statCard("\(stats.listens)", "Listens")
                        statCard("\(stats.likedSongs)", "Liked")
                        statCard("\(stats.playlists)", "Playlists")
                    }
                    .padding(.horizontal, 16)
                }

                SectionHeader("Recently played")
                LazyVStack(spacing: 0) {
                    ForEach(vm.recent) { t in
                        TrackRow(track: t) { player.playNow(t, in: vm.recent) }
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.ink)
        .navigationBarHidden(true)
        .navigationDestination(for: Route.self) { DetailView(route: $0) }
        .overlay { if vm.loading && vm.recent.isEmpty { ProgressView().tint(Theme.fg) } }
        .task { await vm.load() }
    }

    private func statCard(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(SynkFont.sans(24, .heavy)).foregroundStyle(Theme.fg)
            Text(label).font(SynkFont.sans(12)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
