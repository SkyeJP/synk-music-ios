import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var downloads: DownloadStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionLabel("Playback")
                card {
                    pickerRow(title: "Audio quality",
                              selection: $settings.audioQuality,
                              options: SettingsStore.qualityOptions)
                    divider
                    toggleRow("Autoplay related", isOn: $settings.autoplay)
                    divider
                    toggleRow("Gapless playback", isOn: $settings.gapless)
                }

                sectionLabel("Equalizer")
                card {
                    toggleRow("Enable equalizer", isOn: $settings.eqEnabled)
                    divider
                    NavigationLink { EqualizerView() } label: {
                        navRow("Adjust bands", "10-band graphic EQ")
                    }.buttonStyle(.plain)
                }

                sectionLabel("Downloads")
                card {
                    NavigationLink { DownloadsView() } label: {
                        navRow("Downloaded songs", "\(downloads.entries.count) saved for offline")
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.ink)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func sectionLabel(_ t: String) -> some View {
        Eyebrow(text: t).padding(.top, 22).padding(.bottom, 8)
    }
    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .background(Theme.surface1)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private var divider: some View { Divider().overlay(Theme.line).padding(.leading, 16) }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).font(SynkFont.sans(15, .medium)).foregroundStyle(Theme.fg)
        }
        .tint(Theme.fg)
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func navRow(_ title: String, _ subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(SynkFont.sans(15, .medium)).foregroundStyle(Theme.fg)
                Text(subtitle).font(SynkFont.sans(12)).foregroundStyle(Theme.muted)
            }
            Spacer()
            SynkIcon(vector: SynkIcons.chevronRight, size: 16, tint: Theme.faint)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func pickerRow(title: String, selection: Binding<String>, options: [(id: String, label: String)]) -> some View {
        HStack {
            Text(title).font(SynkFont.sans(15, .medium)).foregroundStyle(Theme.fg)
            Spacer()
            Menu {
                ForEach(options, id: \.id) { opt in
                    Button(opt.label) { selection.wrappedValue = opt.id }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(options.first { $0.id == selection.wrappedValue }?.label ?? "Default")
                        .font(SynkFont.sans(14))
                        .foregroundStyle(Theme.muted)
                    SynkIcon(vector: SynkIcons.chevronDown, size: 14, tint: Theme.muted)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}
