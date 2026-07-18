import SwiftUI

struct HomeCard: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var subtitle: String
    var image: String
    var kind: String
    var track: Track?
    var album: Album?
}

struct HomeSectionUI: Identifiable {
    let id = UUID()
    var title: String
    var cards: [HomeCard]
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var sections: [HomeSectionUI] = []
    @Published var loading = false

    func load() async {
        if !sections.isEmpty { return }
        loading = true
        defer { loading = false }
        guard let resp = try? await API.shared.home(limit: 12) else { return }
        sections = resp.sections.compactMap { section in
            let cards: [HomeCard] = section.items.compactMap { item in
                if let t = item.track {
                    return HomeCard(title: t.displayTitle, subtitle: t.artist, image: t.coverURL, kind: "track", track: t)
                } else if let a = item.album {
                    return HomeCard(title: a.displayTitle, subtitle: a.artist, image: a.image, kind: "album", album: a)
                }
                return nil
            }
            return cards.isEmpty ? nil : HomeSectionUI(title: section.title, cards: cards)
        }
    }
}

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var player: PlayerController

    private func greeting() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case ..<5: return "Late night"
        case ..<12: return "Good morning"
        case ..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let name = session.user?.username ?? ""
                Text(name.isEmpty ? greeting() : "\(greeting()), \(name)")
                    .font(SynkFont.sans(23, .heavy))
                    .foregroundStyle(Theme.fg)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                ForEach(vm.sections) { section in
                    Text(section.title)
                        .font(SynkFont.sans(17, .bold))
                        .foregroundStyle(Theme.fg)
                        .padding(.leading, 16)
                        .padding(.top, 22)
                        .padding(.bottom, 12)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 4) {
                            ForEach(section.cards) { card in
                                cardView(card, in: section)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.ink)
        .navigationBarHidden(true)
        .navigationDestination(for: Route.self) { DetailView(route: $0) }
        .overlay {
            if vm.loading && vm.sections.isEmpty { ProgressView().tint(Theme.fg) }
        }
        .task { await vm.load() }
    }

    @ViewBuilder
    private func cardView(_ card: HomeCard, in section: HomeSectionUI) -> some View {
        if let album = card.album {
            NavigationLink(value: Route.album(album.hash)) {
                artworkAndLabels(card)
                    .frame(width: 130)
                    .padding(6)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                if let track = card.track {
                    let queue = section.cards.compactMap { $0.track }
                    player.playNow(track, in: queue)
                }
            } label: {
                artworkAndLabels(card)
                    .frame(width: 130)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
    }

    private func artworkAndLabels(_ card: HomeCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Artwork(url: card.image, round: card.kind == "artist")
                .frame(width: 130, height: 130)
            Text(card.title)
                .font(SynkFont.sans(13, .semibold))
                .foregroundStyle(Theme.fg)
                .lineLimit(1)
            if !card.subtitle.isEmpty {
                Text(card.subtitle)
                    .font(SynkFont.sans(11, .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
        }
    }
}

// Navigation routes for pushed detail screens.
enum Route: Hashable {
    case album(String)
    case artist(String)
    case playlist(String)
}
