import Foundation
import AVFoundation

enum TuningMath {
    static let testBands: [Double] = [63, 125, 250, 500, 2000, 4000, 8000, 12500]

    private static let F: [Double] = [20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500]
    private static let AF: [Double] = [0.532, 0.506, 0.480, 0.455, 0.432, 0.409, 0.387, 0.367, 0.349, 0.330, 0.315, 0.301, 0.288, 0.276, 0.267, 0.259, 0.253, 0.250, 0.246, 0.244, 0.243, 0.243, 0.243, 0.242, 0.242, 0.245, 0.254, 0.271, 0.301]
    private static let LU: [Double] = [-31.6, -27.2, -23.0, -19.1, -15.9, -13.0, -10.3, -8.1, -6.2, -4.5, -3.1, -2.0, -1.1, -0.4, 0.0, 0.3, 0.5, 0.0, -2.7, -4.1, -1.0, 1.7, 2.5, 1.2, -2.1, -7.1, -11.2, -10.7, -3.1]
    private static let TF: [Double] = [78.5, 68.7, 59.5, 51.1, 44.0, 37.5, 31.5, 26.5, 22.1, 17.9, 14.4, 11.4, 8.6, 6.2, 4.4, 3.0, 2.2, 2.4, 3.5, 1.7, -1.3, -4.2, -6.0, -5.4, -1.5, 6.0, 12.6, 13.9, 12.3]

    private static func spl(_ i: Int, _ phon: Double) -> Double {
        let af = 4.47e-3 * (pow(10, 0.025 * phon) - 1.15) + pow(0.4 * pow(10, (TF[i] + LU[i]) / 10 - 9), AF[i])
        return (10 / AF[i]) * log10(af) - LU[i] + 94
    }

    static func equalLoudness(_ freq: Double, phon: Double = 60) -> Double {
        if freq <= F[0] { return spl(0, phon) }
        if freq >= F[F.count - 1] { return spl(F.count - 1, phon) }
        for i in 0..<(F.count - 1) where freq >= F[i] && freq <= F[i + 1] {
            let t = (log(freq) - log(F[i])) / (log(F[i + 1]) - log(F[i]))
            return spl(i, phon) + t * (spl(i + 1, phon) - spl(i, phon))
        }
        return spl(F.count - 1, phon)
    }

    static func expectedOffset(_ f: Double) -> Double { equalLoudness(f) - equalLoudness(1000) }
    static func maxUserOffset(_ f: Double) -> Double { min(18, 30 - expectedOffset(f)) }

    static func fromListeningTest(_ offsets: [Double]) -> DeviceTuning {
        var maxBoost = 0.0
        let filters: [TuneFilter] = testBands.enumerated().map { i, freq in
            let target = i == 0 ? 3.0 : 0.0
            let raw = (i < offsets.count ? offsets[i] : 0) + target
            let gain = (min(6, max(-12, raw)) * 10).rounded() / 10
            maxBoost = max(maxBoost, gain)
            if i == 0 { return TuneFilter(type: "LSC", fc: 90, gain: gain, q: 0.7) }
            if i == testBands.count - 1 { return TuneFilter(type: "HSC", fc: 10000, gain: gain, q: 0.7) }
            return TuneFilter(type: "PK", fc: freq, gain: gain, q: 1.41)
        }
        return DeviceTuning(source: "test", label: "your listening test", preamp: -(maxBoost + 0.5), filters: filters)
    }

    static func key(_ name: String) -> String {
        let collapsed = name.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String(collapsed.prefix(120))
    }
}

/// Follows the current audio output and applies its saved tuning.
@MainActor
final class DeviceTuningManager: ObservableObject {
    static let shared = DeviceTuningManager()
    @Published private(set) var output = "This phone"
    @Published private(set) var profiles: [String: DeviceTuning] = [:]
    private var started = false

    var current: DeviceTuning? { profiles[TuningMath.key(output)] }

    func start() {
        if started { return }
        started = true
        loadCache()
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.detect() }
        }
        detect()
        refresh()
    }

    func refresh() {
        Task {
            guard let list = try? await API.shared.tuningDevices() else { return }
            var m: [String: DeviceTuning] = [:]
            for p in list where !p.deviceKey.isEmpty { m[p.deviceKey] = p }
            profiles = m
            storeCache()
            apply()
        }
    }

    func save(_ profile: DeviceTuning) {
        var p = profile
        p.deviceName = output
        p.deviceKey = TuningMath.key(output)
        profiles[p.deviceKey] = p
        storeCache()
        apply()
        Task { try? await API.shared.saveTuning(p) }
    }

    func setEnabled(_ on: Bool) {
        guard var p = current else { return }
        p.enabled = on
        save(p)
    }

    func removeCurrent() {
        let k = TuningMath.key(output)
        profiles.removeValue(forKey: k)
        storeCache()
        apply()
        Task { try? await API.shared.deleteTuning(k) }
    }

    private func detect() {
        let outs = AVAudioSession.sharedInstance().currentRoute.outputs
        let order: [AVAudioSession.Port] = [.bluetoothA2DP, .bluetoothLE, .usbAudio, .headphones, .bluetoothHFP]
        var name = "This phone"
        if let pick = order.lazy.compactMap({ t in outs.first { $0.portType == t } }).first {
            let raw = pick.portName.trimmingCharacters(in: .whitespaces)
            name = pick.portType == .headphones || raw.isEmpty ? "Wired headphones" : raw
        }
        if name != output {
            output = name
            apply()
        }
    }

    private func apply() {
        if let p = current, p.enabled, !p.filters.isEmpty {
            Equalizer.shared.setTuning(p.filters.map { Equalizer.Tune(type: $0.type, fc: $0.fc, gain: $0.gain, q: $0.q) }, preamp: p.preamp)
        } else {
            Equalizer.shared.setTuning([], preamp: 0)
        }
    }

    private func loadCache() {
        guard let d = UserDefaults.standard.data(forKey: "synk.tuning"),
              let list = try? JSONDecoder().decode([DeviceTuning].self, from: d) else { return }
        profiles = Dictionary(list.map { ($0.deviceKey, $0) }, uniquingKeysWith: { a, _ in a })
        apply()
    }

    private func storeCache() {
        if let d = try? JSONEncoder().encode(Array(profiles.values)) { UserDefaults.standard.set(d, forKey: "synk.tuning") }
    }
}

/// Reference beep at 1 kHz, then the test beep, on repeat, for the listening test.
final class BeepPlayer {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private let lock = NSLock()
    private var freq = 0.0
    private var gainDb = 0.0
    private var pos = 0

    func set(freq f: Double, gainDb g: Double) {
        lock.lock(); freq = f; gainDb = g; lock.unlock()
    }

    func start() {
        if node != nil { return }
        let rate = 48000.0
        let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let beep = Int(0.9 * rate), short = Int(0.15 * rate), long = Int(0.45 * rate)
        let cycle = beep + short + beep + long
        let fade = Int(rate / 40)
        let amp = 0.008 * 2.0.squareRoot()
        pos = 0
        func env(_ k: Int) -> Double {
            if k < fade { return 0.5 - 0.5 * cos(Double.pi * Double(k) / Double(fade)) }
            if k > beep - fade { return 0.5 - 0.5 * cos(Double.pi * Double(beep - k) / Double(fade)) }
            return 1
        }
        let src = AVAudioSourceNode(format: fmt) { [weak self] _, _, frameCount, abl -> OSStatus in
            guard let self else { return noErr }
            self.lock.lock(); let f = self.freq; let g = pow(10, self.gainDb / 20); self.lock.unlock()
            let bufs = UnsafeMutableAudioBufferListPointer(abl)
            for i in 0..<Int(frameCount) {
                let p = self.pos % cycle
                var v = 0.0
                if p < beep {
                    v = sin(2 * Double.pi * 1000 * Double(p) / rate) * amp * env(p)
                } else if f > 0 && p >= beep + short && p < beep + short + beep {
                    let k = p - beep - short
                    v = max(-1, min(1, sin(2 * Double.pi * f * Double(k) / rate) * amp * g * env(k)))
                }
                for b in bufs { b.mData?.assumingMemoryBound(to: Float.self)[i] = Float(v) }
                self.pos += 1
            }
            return noErr
        }
        node = src
        engine.attach(src)
        engine.connect(src, to: engine.mainMixerNode, format: fmt)
        try? engine.start()
    }

    func stop() {
        engine.stop()
        if let node { engine.detach(node) }
        node = nil
    }
}
