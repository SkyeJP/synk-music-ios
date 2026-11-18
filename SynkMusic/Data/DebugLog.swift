import Foundation

/// The last 200 playback, download and network events, shown in Settings >
/// Diagnostics. Problems (not successes) are also sent to the SYNK server,
/// which posts them to the team's diagnostics channel.
@MainActor
final class DebugLog: ObservableObject {
    static let shared = DebugLog()
    @Published private(set) var lines: [String] = []
    private var outbox: [String] = []
    private var flushTask: Task<Void, Never>?
    private var lastSent: [String: Date] = [:]
    private let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// `issue: false` keeps a line on the phone only (for example "played from cache").
    func add(_ s: String, issue: Bool = true) {
        let line = "\(fmt.string(from: Date())) \(s)"
        lines.append(line)
        if lines.count > 200 { lines.removeFirst(lines.count - 200) }
        if issue && !DebugLog.isCancellation(s) { queue(s, line) }
    }

    func clear() { lines = [] }

    /// Requests the app itself stopped (leaving a page, skipping a song) are not problems.
    static func isCancellation(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.hasSuffix(": cancelled") || l.hasSuffix(": canceled") || l.contains("cancellationerror")
    }

    nonisolated static func log(_ s: String, issue: Bool = true) {
        Task { @MainActor in DebugLog.shared.add(s, issue: issue) }
    }

    private func queue(_ message: String, _ line: String) {
        if let last = lastSent[message], Date().timeIntervalSince(last) < 60 { return }
        lastSent[message] = Date()
        outbox.append(line)
        if outbox.count >= 20 { flush() } else if flushTask == nil {
            flushTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                self?.flush()
            }
        }
    }

    private func flush() {
        flushTask?.cancel()
        flushTask = nil
        let batch = Array(outbox.prefix(30))
        outbox.removeFirst(batch.count)
        guard !batch.isEmpty, let token = AuthStore.shared.token, !token.isEmpty else { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        var req = URLRequest(url: API.base.appendingPathComponent("diagnostics"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(API.userAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["platform": "ios", "version": version, "lines": batch] as [String: Any])
        URLSession.shared.dataTask(with: req).resume()
    }
}
