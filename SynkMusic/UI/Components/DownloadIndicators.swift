import SwiftUI

/// The small mark before a song's "...": an empty ring while queued, a ring
/// filling while it downloads, a filled download mark once it is saved.
struct DownloadMark: View {
    let track: Track
    @ObservedObject private var downloads = DownloadStore.shared

    var body: some View {
        let k = downloads.key(track)
        Group {
            if downloads.entries[k] != nil {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.fg.opacity(0.35))
                    .accessibilityLabel("Downloaded")
            } else if downloads.downloading.contains(k) {
                ProgressRing(value: downloads.progress[k] ?? 0, size: 13, line: 1.6)
                    .accessibilityLabel(downloads.progress[k] == nil ? "Waiting to download" : "Downloading")
            }
        }
        .frame(width: 18)
    }
}

struct ProgressRing: View {
    let value: Double
    var size: CGFloat = 14
    var line: CGFloat = 2

    var body: some View {
        ZStack {
            Circle().stroke(Theme.fg.opacity(0.3), lineWidth: line)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, value)))
                .stroke(Theme.fg.opacity(0.9), style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: value)
        }
        .frame(width: size, height: size)
    }
}

/// The round download button beside Play: an arrow, then a ring with a stop
/// square while the songs download (tap to stop), then a check when all are saved.
struct CollectionDownloadButton: View {
    let tracks: [Track]
    var size: CGFloat = 48
    @ObservedObject private var downloads = DownloadStore.shared

    var body: some View {
        let keys = tracks.map { downloads.key($0) }
        let busy = keys.contains { downloads.downloading.contains($0) }
        let done = !tracks.isEmpty && keys.allSatisfy { downloads.entries[$0] != nil }
        Button {
            if busy { downloads.cancel(tracks) } else if !done { tracks.forEach { downloads.download($0) } }
        } label: {
            ZStack {
                if busy {
                    ProgressRing(value: downloads.fraction(tracks), size: size * 0.46, line: 2.2)
                    RoundedRectangle(cornerRadius: 1.5).fill(Theme.fg).frame(width: size * 0.15, height: size * 0.15)
                } else {
                    Image(systemName: done ? "checkmark" : "arrow.down")
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundStyle(Theme.fg)
                }
            }
            .glassCircle(size)
        }
        .buttonStyle(PressStyle())
        .disabled(tracks.isEmpty)
        .accessibilityLabel(busy ? "Stop downloading" : done ? "Downloaded" : "Download")
    }
}
