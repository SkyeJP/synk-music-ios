import Foundation

struct LtState: Equatable {
    var active = false
    var connecting = false
    var role: String?
    var partyId: String?
    var listenerCount = 0
    var hostName = ""
    var error: String?
}

/// Listen Together over wss://synkmusic.co.uk/lt, a port of Android's LtClient.
@MainActor
final class LtClient: ObservableObject {
    static let shared = LtClient()
    private static let url = URL(string: "wss://synkmusic.co.uk/lt")!

    @Published private(set) var state = LtState()

    private let player = PlayerController.shared
    private var ws: URLSessionWebSocketTask?
    private var hostSync: Task<Void, Never>?
    private var reconnect: Task<Void, Never>?
    private var pinger: Task<Void, Never>?
    private var lastHostIndex = -1
    private var lastHostPlaying = false
    private var lastHostSig = ""

    var shareLink: String { state.partyId.map { "https://synkmusic.co.uk/?lt=\($0)" } ?? "" }

    func start() {
        if state.connecting { return }
        state.connecting = true
        state.error = nil
        Task {
            let id = (try? await API.shared.ltCreateParty()) ?? ""
            if id.isEmpty {
                state.connecting = false
                state.error = "Failed to create session"
                return
            }
            open(id, host: true)
        }
    }

    func join(_ raw: String) {
        let id = raw.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, state.partyId != id else { return }
        state.connecting = true
        state.error = nil
        Task {
            guard let info = try? await API.shared.ltInfo(id), !info.partyId.isEmpty else {
                state.connecting = false
                state.error = "Session not found or has ended"
                return
            }
            state.hostName = info.hostName.isEmpty ? "Someone" : info.hostName
            open(id, host: false)
        }
    }

    private func open(_ id: String, host: Bool) {
        reconnect?.cancel()
        ws?.cancel(with: .normalClosure, reason: nil)
        let task = URLSession.shared.webSocketTask(with: LtClient.url)
        ws = task
        task.resume()
        let hello: JSON = host
            ? ["type": "lt:host", "partyId": id, "state": snapshot(player.snapshot())]
            : ["type": "lt:join", "partyId": id]
        task.send(.string(RealtimeJSON.string(hello))) { _ in }
        receive(task, id)
        pinger?.cancel()
        pinger = Task { [weak self, weak task] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard let task, self?.ws === task else { return }
                task.sendPing { _ in }
            }
        }
    }

    private func receive(_ task: URLSessionWebSocketTask, _ id: String) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.ws === task else { return }
                switch result {
                case .success(let msg):
                    if case .string(let text) = msg, let obj = RealtimeJSON.parse(text) { self.handle(obj) }
                    if self.ws === task { self.receive(task, id) }
                case .failure:
                    self.dropped(id)
                }
            }
        }
    }

    private func dropped(_ id: String) {
        ws = nil
        if state.active && state.role == "listener" {
            state.connecting = true
            reconnect = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if !Task.isCancelled { self?.open(id, host: false) }
            }
        } else if state.active && state.role == "host" {
            stopHostSync()
            state = LtState(error: "Connection lost, the session has ended")
        } else {
            state.connecting = false
            if state.error == nil { state.error = "Connection failed" }
        }
    }

    private func handle(_ o: JSON) {
        switch o.str("type") {
        case "lt:connected":
            let role = o.str("role")
            state.active = true
            state.connecting = false
            state.role = role
            state.partyId = o.str("partyId") ?? state.partyId
            state.error = nil
            if role == "host" { startHostSync() }
        case "lt:listeners": state.listenerCount = o.int("count") ?? 0
        case "lt:error":
            let msg = o.str("message") ?? "Something went wrong"
            reset()
            state = LtState(error: msg)
        case "lt:state": if state.role == "listener" { applyState(o["state"] as? JSON) }
        case "lt:action": if state.role == "listener" { applyAction(o.str("action"), o["state"] as? JSON) }
        case "lt:ended":
            reset()
            state = LtState(error: "The session has ended")
        default: break
        }
    }

    private func sig(_ s: PlayerSnapshot) -> String { s.queue.map { $0.hash }.joined(separator: ",") }

    private func startHostSync() {
        stopHostSync()
        let p = player.snapshot()
        lastHostIndex = p.index
        lastHostPlaying = p.isPlaying
        lastHostSig = sig(p)
        hostSync = Task { [weak self] in
            var lastState = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self, self.state.active, self.state.role == "host" else { continue }
                let s = self.player.snapshot()
                let q = self.sig(s)
                if s.current != nil && (s.index != self.lastHostIndex || q != self.lastHostSig) {
                    let action = q != self.lastHostSig ? "play" : s.index == self.lastHostIndex + 1 ? "next" : s.index == self.lastHostIndex - 1 ? "prev" : "play"
                    self.lastHostIndex = s.index
                    self.lastHostSig = q
                    self.lastHostPlaying = s.isPlaying
                    self.sendAction(action, s, trackChange: true)
                    lastState = Uptime.ms
                    continue
                }
                if s.isPlaying != self.lastHostPlaying && s.current != nil {
                    self.lastHostPlaying = s.isPlaying
                    self.sendAction(s.isPlaying ? "resume" : "pause", s, trackChange: false)
                    lastState = Uptime.ms
                    continue
                }
                if Uptime.ms - lastState >= 2000 {
                    lastState = Uptime.ms
                    self.send(["type": "lt:state", "state": self.snapshot(s)])
                }
            }
        }
    }

    private func stopHostSync() { hostSync?.cancel(); hostSync = nil }

    private func sendAction(_ action: String, _ s: PlayerSnapshot, trackChange: Bool) {
        send(["type": "lt:action", "action": action, "state": snapshot(s, zeroTime: trackChange)])
    }

    private func send(_ o: JSON) { ws?.send(.string(RealtimeJSON.string(o))) { _ in } }

    private func snapshot(_ s: PlayerSnapshot, zeroTime: Bool = false) -> JSON {
        let pos = zeroTime ? 0 : s.positionMs
        return [
            "queue": s.queue.prefix(200).map { t -> JSON in
                var o = RealtimeJSON.track(t)
                o.removeValue(forKey: "coverUrl")
                return o
            },
            "queueIndex": max(0, s.index),
            "currentTrack": s.current.map { RealtimeJSON.track($0) as Any } ?? (NSNull() as Any),
            "isPlaying": s.isPlaying,
            "currentTime": Double(pos) / 1000,
            "positionMs": pos,
        ]
    }

    private func positionMs(_ st: JSON) -> Int? {
        st.double("positionMs").map { Int($0) } ?? st.double("currentTime").map { Int($0 * 1000) }
    }

    private func applyState(_ st: JSON?) {
        guard let st else { return }
        let local = player.snapshot()
        let queue = RealtimeJSON.tracks(st["queue"])
        let idx = st.int("queueIndex")
        let hostPlaying = st.bool("isPlaying")
        if !queue.isEmpty && queue.map({ $0.hash }).joined(separator: ",") != sig(local) {
            player.playQueue(queue, start: min(max(0, idx ?? 0), queue.count - 1), positionMs: positionMs(st) ?? 0, autoplay: hostPlaying ?? true)
            return
        }
        if let idx, idx != local.index, !local.queue.isEmpty {
            player.playIndex(idx)
            return
        }
        if hostPlaying == true && !local.isPlaying && local.current != nil { player.play() }
        if hostPlaying == false && local.isPlaying { player.pause() }
        if let pos = positionMs(st), abs(player.positionMs - pos) > 2000 { player.seek(ms: pos) }
    }

    private func applyAction(_ action: String?, _ st: JSON?) {
        let local = player.snapshot()
        switch action {
        case "pause": if local.isPlaying { player.pause() }
        case "resume": if !local.isPlaying && local.current != nil { player.play() }
        case "next", "prev", "play":
            var queue = st.map { RealtimeJSON.tracks($0["queue"]) } ?? []
            if queue.isEmpty { queue = local.queue }
            let idx = st?.int("queueIndex") ?? local.index
            if !queue.isEmpty { player.playQueue(queue, start: min(max(0, idx), queue.count - 1)) }
        case "seek": if let st, let p = positionMs(st) { player.seek(ms: p) }
        default: break
        }
    }

    func end() {
        if state.role == "host" { send(["type": "lt:end"]) }
        reset()
    }

    func leave() {
        if state.role == "listener" { send(["type": "lt:leave"]) }
        reset()
    }

    private func reset() {
        stopHostSync()
        reconnect?.cancel(); reconnect = nil
        pinger?.cancel(); pinger = nil
        let s = ws
        ws = nil
        s?.cancel(with: .normalClosure, reason: nil)
        state = LtState()
    }
}
