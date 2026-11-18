import Foundation
import Network

/// Playback settings, the same keys and choices as the Android app.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    static let qualities = [("default", "Default"), ("flac", "Lossless"), ("320", "High (320)"), ("128", "Standard (128)")]
    static let bandFreqs: [Double] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    private let d = UserDefaults.standard

    @Published var audioQuality: String { didSet { d.set(audioQuality, forKey: "audioQuality") } }
    @Published var autoplay: Bool { didSet { d.set(autoplay, forKey: "autoplay") } }
    @Published var gapless: Bool { didSet { d.set(gapless, forKey: "gapless") } }
    @Published var eqEnabled: Bool { didSet { d.set(eqEnabled, forKey: "eqEnabled"); pushEq() } }
    @Published var eqBands: [Double] { didSet { d.set(eqBands, forKey: "eqBands"); pushEq() } }

    private init() {
        let d = UserDefaults.standard
        audioQuality = SettingsStore.normalize(d.string(forKey: "audioQuality"))
        autoplay = d.object(forKey: "autoplay") as? Bool ?? true
        gapless = d.object(forKey: "gapless") as? Bool ?? false
        eqEnabled = d.bool(forKey: "eqEnabled")
        let raw = d.array(forKey: "eqBands") as? [Double] ?? []
        eqBands = (0..<10).map { $0 < raw.count ? raw[$0] : 0 }
        pushEq()
    }

    /// Quality to ask the server for, nil for its default.
    var requestQuality: String? { audioQuality == "default" ? nil : audioQuality }

    private func pushEq() { Equalizer.shared.setBands(enabled: eqEnabled, gains: eqBands) }

    static func normalize(_ raw: String?) -> String {
        switch raw?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "flac", "lossless", "hires", "hi-res": return "flac"
        case "320", "256", "high": return "320"
        case "128", "standard", "low": return "128"
        default: return "default"
        }
    }
}

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    @Published private(set) var online = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let on = path.status == .satisfied
            Task { @MainActor in if self?.online != on { self?.online = on } }
        }
        monitor.start(queue: DispatchQueue(label: "synk.net"))
    }
}

enum Format {
    static func time(_ sec: Int) -> String {
        let s = max(0, sec)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func durationLong(_ sec: Int) -> String {
        if sec <= 0 { return "0 min" }
        let d = sec / 86400, h = (sec % 86400) / 3600, m = (sec % 3600) / 60
        if d > 0 { return "\(d) \(d == 1 ? "day" : "days") \(h) hr" }
        if h > 0 { return "\(h) hr \(m) min" }
        return "\(m) min"
    }

    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1f", Double(n) / 1_000_000).replacingOccurrences(of: ".0", with: "") + "m" }
        if n >= 1000 { return String(format: "%.1f", Double(n) / 1000).replacingOccurrences(of: ".0", with: "") + "k" }
        return String(n)
    }

    static func plural(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
}
