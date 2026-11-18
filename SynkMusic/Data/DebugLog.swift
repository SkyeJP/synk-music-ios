import Foundation

/// The last 200 playback, download and network problems, shown in Settings >
/// Diagnostics so they can be copied and sent when something goes wrong.
@MainActor
final class DebugLog: ObservableObject {
    static let shared = DebugLog()
    @Published private(set) var lines: [String] = []
    private let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    func add(_ s: String) {
        lines.append("\(fmt.string(from: Date())) \(s)")
        if lines.count > 200 { lines.removeFirst(lines.count - 200) }
    }

    func clear() { lines = [] }

    /// From any thread.
    nonisolated static func log(_ s: String) {
        Task { @MainActor in DebugLog.shared.add(s) }
    }
}
