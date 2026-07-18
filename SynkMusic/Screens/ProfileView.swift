import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var showSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                let user = session.user
                Artwork(url: user?.avatarUrl ?? "", round: true)
                    .frame(width: 96, height: 96)
                    .padding(.top, 24)

                Text(user?.username ?? "")
                    .font(SynkFont.sans(22, .bold))
                    .foregroundStyle(Theme.fg)
                    .padding(.top, 12)
                if let email = user?.email, !email.isEmpty {
                    Text(email).font(SynkFont.sans(13)).foregroundStyle(Theme.muted)
                }

                if let bio = user?.bio, !bio.isEmpty {
                    Text(bio)
                        .font(SynkFont.sans(14))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32).padding(.top, 8)
                }

                VStack(spacing: 0) {
                    Button { showSettings = true } label: {
                        profileRow(icon: SynkIcons.settings, title: "Settings")
                    }.buttonStyle(.plain)

                    Divider().overlay(Theme.line)

                    Button { session.logout() } label: {
                        profileRow(icon: SynkIcons.logout, title: "Log out")
                    }.buttonStyle(.plain)
                }
                .background(Theme.surface1)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16).padding(.top, 24)
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.ink)
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $showSettings) { SettingsView() }
    }

    private func profileRow(icon: SynkVector, title: String) -> some View {
        HStack(spacing: 14) {
            SynkIcon(vector: icon, size: 20, tint: Theme.fg)
            Text(title).font(SynkFont.sans(15, .medium)).foregroundStyle(Theme.fg)
            Spacer()
            SynkIcon(vector: SynkIcons.chevronRight, size: 16, tint: Theme.faint)
        }
        .padding(.horizontal, 16).padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}
