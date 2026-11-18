import SwiftUI

enum Durations {
    /// "286 songs, 15 hours 38 minutes", as Apple Music words it.
    static func summary(_ tracks: [Track]) -> String {
        let mins = tracks.reduce(0) { $0 + $1.durationSeconds } / 60
        let time = mins >= 60
            ? "\(Format.plural(mins / 60, "hour", "hours")) \(Format.plural(mins % 60, "minute", "minutes"))"
            : Format.plural(mins, "minute", "minutes")
        return "\(Format.plural(tracks.count, "song", "songs")), \(time)"
    }
}

private func addSongs(_ playlist: String, _ songs: [Track]) async -> Bool {
    let hashes = songs.map { $0.hash.isEmpty ? ($0.isrc ?? "") : $0.hash }.filter { !$0.isEmpty }
    guard !hashes.isEmpty else { return false }
    return (try? await API.shared.addToPlaylist(playlist, hashes: hashes)) != nil
}

/// The "+ Add Music" row at the end of your own playlist.
struct AddMusicRow: View {
    let playlistId: String
    let onAdded: () -> Void
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus").font(.system(size: 22, weight: .medium)).foregroundStyle(Theme.fg)
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.1)))
                Text("Add Music").font(sans: 16).foregroundStyle(Theme.fg)
                Spacer()
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
            .hairline(70)
        }
        .buttonStyle(.plain)
        .padding(.leading, 6)
        .sheet(isPresented: $open) {
            AddMusicSheet(playlistId: playlistId, onAdded: onAdded)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// Search the catalogue and add songs to a playlist with "+".
struct AddMusicSheet: View {
    let playlistId: String
    let onAdded: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = SearchModel()
    @State private var added: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array((search.result?.tracks ?? []).enumerated()), id: \.offset) { _, t in
                    HStack(spacing: 12) {
                        Artwork(url: t.coverUrl, radius: 6).frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.displayTitle).font(sans: 16).foregroundStyle(Theme.fg).lineLimit(1)
                            Text(t.artist).font(sans: 13).foregroundStyle(Theme.fg.opacity(0.55)).lineLimit(1)
                        }
                        Spacer()
                        Button {
                            Task {
                                if await addSongs(playlistId, [t]) { added.insert(t.hash); onAdded() }
                            }
                        } label: {
                            Image(systemName: added.contains(t.hash) ? "checkmark.circle.fill" : "plus.circle")
                                .font(.system(size: 24)).foregroundStyle(Theme.fg)
                        }
                        .buttonStyle(.plain)
                        .disabled(added.contains(t.hash))
                        .accessibilityLabel(added.contains(t.hash) ? "Added" : "Add \(t.displayTitle)")
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.base)
            .searchable(text: $search.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Artists, Songs, Albums")
            .onChange(of: search.query) { _, q in search.change(q) }
            .navigationTitle("Add Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// "Suggested Songs: Preview and add to playlist", from the radio mixes of a
/// few of the playlist's artists, without songs it already has.
struct SuggestedSongs: View {
    let playlistId: String
    let tracks: [Track]
    let onAdded: () -> Void
    @Environment(\.playTrack) private var play
    @State private var songs: [Track] = []
    @State private var loading = false
    @State private var spin = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Suggested Songs").font(sans: 20, 700).foregroundStyle(Theme.fg)
                    Text("Preview and add to playlist").font(sans: 16).foregroundStyle(Theme.fg.opacity(0.6))
                }
                Spacer()
                Button { Task { await load() } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.fg)
                        .rotationEffect(.degrees(spin))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New suggestions")
            }
            .padding(.bottom, 10)
            if songs.isEmpty {
                Text(loading ? "Finding songs" : "No suggestions right now.").font(sans: 14).foregroundStyle(Theme.fg.opacity(0.5))
                    .padding(.vertical, 20)
            }
            ForEach(Array(songs.enumerated()), id: \.offset) { i, t in
                HStack(spacing: 12) {
                    Artwork(url: t.coverUrl, radius: 6).frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(t.displayTitle).font(sans: 16).foregroundStyle(Theme.fg).lineLimit(1)
                            if t.explicit {
                                Text("E").font(sans: 9, 700).foregroundStyle(.black).padding(.horizontal, 3)
                                    .background(RoundedRectangle(cornerRadius: 2).fill(Theme.fg.opacity(0.55)))
                            }
                        }
                        Text(t.artist).font(sans: 13).foregroundStyle(Theme.fg.opacity(0.55)).lineLimit(1)
                    }
                    Spacer()
                    Button {
                        Task {
                            if await addSongs(playlistId, [t]) {
                                withAnimation { _ = songs.remove(at: songs.firstIndex(of: t) ?? i) }
                                onAdded()
                            }
                        }
                    } label: {
                        Image(systemName: "plus.circle").font(.system(size: 24)).foregroundStyle(Theme.fg)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(t.displayTitle)")
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .onTapGesture { play(t, [t]) }
                .hairline(60)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.08)))
        .padding(.horizontal, 16)
        .padding(.top, 28)
        .task { if songs.isEmpty { await load() } }
    }

    private func load() async {
        loading = true
        withAnimation(.easeInOut(duration: 0.6)) { spin += 360 }
        let have = Set(tracks.map { $0.hash })
        let artists = Array(Set(tracks.map { $0.artist }.filter { !$0.isEmpty })).shuffled().prefix(3)
        var pool: [Track] = []
        await withTaskGroup(of: [Track].self) { g in
            for a in artists { g.addTask { (try? await API.shared.artistRadio(a)) ?? [] } }
            for await list in g { pool += list }
        }
        var seen = have
        songs = Array(pool.shuffled().filter { !$0.hash.isEmpty && seen.insert($0.hash).inserted }.prefix(5))
        loading = false
    }
}

/// Rename a playlist, change its description, make it public or private.
struct EditPlaylistSheet: View {
    let id: String
    @State var name: String
    @State var description: String
    let onSaved: () -> Void
    @State private var isPublic = false
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(id: String, name: String, description: String, onSaved: @escaping () -> Void) {
        self.id = id
        _name = State(initialValue: name)
        _description = State(initialValue: description)
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("Playlist name", text: $name) }
                Section("Description") { TextField("Description", text: $description, axis: .vertical).lineLimit(3...6) }
                Section { Toggle("Public", isOn: $isPublic).tint(Theme.fg) }
                if let error { Section { Text(error).foregroundStyle(Theme.danger) } }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.base)
            .navigationTitle("Edit Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            do {
                                try await API.shared.updatePlaylist(id, name: name.trimmingCharacters(in: .whitespaces),
                                                                    description: description, isPublic: isPublic)
                                onSaved()
                                dismiss()
                            } catch {
                                self.error = (error as? APIError)?.message ?? "Couldn't save."
                            }
                            saving = false
                        }
                    }
                    .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
