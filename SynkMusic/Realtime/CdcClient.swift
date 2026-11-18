import Foundation
import UIKit
import Combine

struct CdcDevice: Identifiable, Equatable {
    var id: String { deviceId }
    let deviceId: String
    var name: String
    var type: String
    var isActive = false
    var online = true
}

struct RemotePlaybackState: Equatable {
    var currentTrack: Track?
    var isPlaying = false
    var positionMs = 0
    var durationMs = 0
    var queue: [Track] = []
    var index = 0
    var volume: Float = 1
    var shuffle = false
    var repeatMode = "off"
    var receivedAt = Uptime.ms

    func position(at now: Int = Uptime.ms) -> Int {
        let p = isPlaying ? positionMs + max(0, now - receivedAt) : positionMs
        return durationMs > 0 ? min(p, durationMs) : p
    }
}

enum Uptime {
    static var ms: Int { Int(ProcessInfo.processInfo.systemUptime * 1000) }
}

/// SYNK Connect: lists your devices over server-sent events, publishes this
/// phone's playback while it is the active device, and takes commands and
/// transfers from the others. A port of Android's CdcClient.
@MainActor
final class CdcClient: ObservableObject {
    static let shared = CdcClient()
    private static let base = "https://synkmusic.co.uk"
    private static let backoff: [UInt64] = [1000, 2000, 5000, 10000]
    private static let envelope: Set<String> = ["command", "params", "fromDeviceId", "targetDeviceId", "deviceId"]

    @Published private(set) var devices: [CdcDevice] = []
    @Published private(set) var activeId: String?
    @Published private(set) var connected = false
    @Published private(set) var remoteState: RemotePlaybackState?

    let selfId = AuthStore.shared.deviceId
    private let player = PlayerController.shared
    private var streamTask: Task<Void, Never>?
    private var publishTask: Task<Void, Never>?
    private var watch: AnyCancellable?
    private var token = ""
    private var claimPending = false
    private var lastSig = ""
    private var lastAt = 0
    private var lastPos = 0
    private var lastPlaying = false
    private var forcePublish = false

    var isRemote: Bool { activeId != nil && activeId != selfId }
    var activeDevice: CdcDevice? { devices.first { $0.deviceId == activeId } }
    private var isActiveHere: Bool { activeId == selfId }

    func connect() {
        if streamTask == nil {
            streamTask = Task { [weak self] in
                var attempt = 0
                while !Task.isCancelled {
                    guard let self else { return }
                    guard let tok = AuthStore.shared.token, !tok.isEmpty else {
                        try? await Task.sleep(nanoseconds: CdcClient.backoff.last! * 1_000_000)
                        continue
                    }
                    self.token = tok
                    let opened = await self.runStream()
                    self.connected = false
                    if opened { attempt = 0 }
                    try? await Task.sleep(nanoseconds: CdcClient.backoff[min(attempt, CdcClient.backoff.count - 1)] * 1_000_000)
                    attempt += 1
                }
            }
        }
        if publishTask == nil {
            publishTask = Task { [weak self] in
                while !Task.isCancelled {
                    self?.maybePublish()
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
        }
        if watch == nil {
            watch = player.$isPlaying.removeDuplicates().sink { [weak self] playing in
                if playing { Task { @MainActor in self?.onLocalPlaybackStarted() } }
            }
        }
    }

    func disconnect() {
        streamTask?.cancel(); streamTask = nil
        publishTask?.cancel(); publishTask = nil
        watch = nil
        token = ""
        claimPending = false
        lastSig = ""
        lastAt = 0
        connected = false
        devices = []
        activeId = nil
        remoteState = nil
    }

    /// Reads the event stream until it ends. True when it connected at all.
    private func runStream() async -> Bool {
        let name = UIDevice.current.name
        var comps = URLComponents(string: "\(CdcClient.base)/api/sync/stream")!
        comps.queryItems = [.init(name: "deviceId", value: selfId), .init(name: "name", value: name), .init(name: "type", value: "mobile")]
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 45
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(API.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return false }
            connected = true
            var event = "message"
            var data = ""
            var line = Data()
            for try await b in bytes {
                if Task.isCancelled { break }
                if b != 0x0A { line.append(b); continue }
                var text = String(decoding: line, as: UTF8.self)
                line.removeAll(keepingCapacity: true)
                if text.hasSuffix("\r") { text.removeLast() }
                if text.isEmpty {
                    if !data.isEmpty { handle(event, data) }
                    data = ""
                    event = "message"
                } else if text.hasPrefix(":") {
                    continue
                } else if text.hasPrefix("event:") {
                    event = text.dropFirst(6).trimmingCharacters(in: .whitespaces)
                } else if text.hasPrefix("data:") {
                    var v = String(text.dropFirst(5))
                    if v.hasPrefix(" ") { v.removeFirst() }
                    data += data.isEmpty ? v : "\n" + v
                }
            }
            return true
        } catch {
            return connected
        }
    }

    private func handle(_ type: String, _ data: String) {
        guard let obj = RealtimeJSON.parse(data) else { return }
        switch type {
        case "connected": parseDevices(obj); reconcileAfterConnect()
        case "devices": parseDevices(obj)
        case "device-disconnected":
            guard let gone = obj.str("deviceId") else { return }
            devices = devices.map { $0.deviceId == gone ? CdcDevice(deviceId: $0.deviceId, name: $0.name, type: $0.type, isActive: false, online: false) : $0 }
            if activeId == gone { activeId = nil; remoteState = nil }
        case "command": handleCommand(obj)
        case "state-update": handleState(obj)
        case "transfer": handleTransfer(obj)
        default: break
        }
    }

    private func parseDevices(_ obj: JSON) {
        if let arr = obj["devices"] as? [JSON] {
            devices = arr.compactMap { o in
                guard let id = o.str("deviceId") else { return nil }
                return CdcDevice(deviceId: id, name: o.str("name") ?? "Device", type: o.str("type") ?? "web",
                                 isActive: o.bool("isActive") ?? false, online: o.bool("online") ?? true)
            }
        }
        if obj.keys.contains("activeDeviceId") {
            let act = obj.str("activeDeviceId").flatMap { $0.isEmpty ? nil : $0 }
            if act != activeId {
                activeId = act
                if act == nil || act == selfId { remoteState = nil }
            }
        }
    }

    private func reconcileAfterConnect() {
        guard player.isPlaying, activeId != selfId else { return }
        if activeId == nil { claim() } else { player.pause() }
    }

    private func onLocalPlaybackStarted() {
        guard !token.isEmpty, connected, activeId != selfId else { return }
        claim()
    }

    private func claim() {
        claimPending = true
        activeId = selfId
        remoteState = nil
        post("/api/sync/command", ["command": "transfer", "deviceId": selfId, "targetDeviceId": selfId, "state": localState(player.snapshot())])
        forcePublish = true
    }

    private func maybePublish() {
        guard !token.isEmpty, isActiveHere else { return }
        let p = player.snapshot()
        guard let cur = p.current else { return }
        let now = Uptime.ms
        let sig = "\(cur.hash)|\(p.isPlaying)|\(p.index)|\(p.shuffle)|\(p.repeatMode.rawValue)|\(p.volume)|\(p.queue.count)|\(p.queue.map { $0.hash }.joined(separator: ",").hashValue)"
        let expected = lastPos + (lastPlaying ? now - lastAt : 0)
        let seeked = abs(p.positionMs - expected) > 2000
        let periodic = p.isPlaying && now - lastAt >= 5000
        guard forcePublish || sig != lastSig || seeked || periodic else { return }
        guard now - lastAt >= 500 else { return }
        forcePublish = false
        lastSig = sig
        lastAt = now
        lastPos = p.positionMs
        lastPlaying = p.isPlaying
        post("/api/sync/state", ["deviceId": selfId, "state": localState(p)])
    }

    private func localState(_ p: PlayerSnapshot) -> JSON {
        let q = Array(p.queue.prefix(200))
        let idx = q.indices.contains(p.index) ? p.index : 0
        return [
            "currentTrack": p.current.map { RealtimeJSON.track($0) as Any } ?? (NSNull() as Any),
            "queue": q.map { RealtimeJSON.track($0) },
            "queueIndex": idx, "index": idx,
            "isPlaying": p.isPlaying,
            "currentTime": Double(p.positionMs) / 1000, "positionMs": p.positionMs,
            "duration": Double(p.durationMs) / 1000, "durationMs": p.durationMs,
            "volume": Double(p.volume), "shuffle": p.shuffle, "repeatMode": p.repeatMode.name,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
        ]
    }

    private func handleState(_ obj: JSON) {
        guard let from = obj.str("fromDeviceId"), from != selfId else { return }
        let playing = obj.bool("isPlaying") ?? false
        if activeId != from {
            if activeId != nil && !playing { return }
            activeId = from
            if player.isPlaying { player.pause() }
        }
        remoteState = parseRemote(obj)
    }

    private func parseRemote(_ o: JSON) -> RemotePlaybackState {
        let queue = RealtimeJSON.tracks(o["queue"])
        let cur = RealtimeJSON.parseTrack(o["currentTrack"])
        let idx = o.int("queueIndex") ?? o.int("index") ?? max(0, queue.firstIndex { $0.hash == cur?.hash } ?? 0)
        return RemotePlaybackState(
            currentTrack: cur ?? (queue.indices.contains(idx) ? queue[idx] : nil),
            isPlaying: o.bool("isPlaying") ?? false,
            positionMs: RealtimeJSON.positionMs(o, "positionMs", "currentTime"),
            durationMs: RealtimeJSON.positionMs(o, "durationMs", "duration"),
            queue: queue, index: idx,
            volume: Float(min(1, max(0, o.double("volume") ?? 1))),
            shuffle: o.bool("shuffle") ?? false,
            repeatMode: o.str("repeatMode") ?? "off")
    }

    private func handleCommand(_ obj: JSON) {
        let target = obj.str("targetDeviceId").flatMap { $0.isEmpty ? nil : $0 }
        if let target, target != selfId { return }
        if target == nil && !isActiveHere { return }
        guard let command = obj.str("command") else { return }
        var params = obj.filter { !CdcClient.envelope.contains($0.key) }
        if let nested = obj["params"] as? JSON { params.merge(nested) { _, n in n } }
        switch command {
        case "play": player.play()
        case "pause": player.pause()
        case "toggle": player.toggle()
        case "next": player.next()
        case "prev", "previous": player.prev()
        case "seek":
            if let ms = params.double("positionMs") ?? params.double("position").map({ $0 * 1000 }) { player.seek(ms: Int(ms)) }
        case "setVolume": if let v = params.double("volume") { player.setVolume(Float(v)) }
        case "toggleShuffle": player.toggleShuffle()
        case "cycleRepeat": player.cycleRepeat()
        case "playIndex": if let i = params.int("index") { player.playIndex(i) }
        case "playQueue":
            let tracks = RealtimeJSON.tracks(params["tracks"])
            if !tracks.isEmpty { player.playQueue(tracks, start: min(max(0, params.int("startIndex") ?? 0), tracks.count - 1)) }
        case "addNext": if let t = RealtimeJSON.parseTrack(params["track"]) { player.addNext(t) }
        case "addToQueue": if let t = RealtimeJSON.parseTrack(params["track"]) { player.addToQueue(t) }
        case "clearQueue": player.clearUpcoming()
        case "removeFromQueue": if let i = params.int("queueIndex") { player.removeFromQueue(i) }
        case "moveInQueue": if let f = params.int("from"), let t = params.int("to") { player.moveInQueue(from: f, to: t) }
        default: break
        }
        forcePublish = true
    }

    private func handleTransfer(_ obj: JSON) {
        guard let target = obj.str("targetDeviceId") else { return }
        let from = obj.str("fromDeviceId")
        let st = obj["state"] as? JSON
        if target != selfId {
            claimPending = false
            if player.isPlaying { player.pause() }
            activeId = target
            remoteState = st.map { parseRemote($0) }.flatMap { $0.currentTrack == nil ? nil : $0 }
            return
        }
        activeId = selfId
        remoteState = nil
        if from == selfId && claimPending {
            claimPending = false
            forcePublish = true
            return
        }
        claimPending = false
        if let st { applyTransfer(st) }
        forcePublish = true
    }

    private func applyTransfer(_ st: JSON) {
        var queue = RealtimeJSON.tracks(st["queue"])
        let cur = RealtimeJSON.parseTrack(st["currentTrack"])
        var idx = st.int("queueIndex") ?? st.int("index") ?? (queue.firstIndex { $0.hash == cur?.hash } ?? 0)
        if queue.isEmpty, let cur { queue = [cur]; idx = 0 }
        guard !queue.isEmpty else { return }
        idx = min(max(0, idx), queue.count - 1)
        player.playQueue(queue, start: idx, positionMs: RealtimeJSON.positionMs(st, "positionMs", "currentTime"), autoplay: st.bool("isPlaying") ?? true)
        if let s = st.bool("shuffle") { player.setShuffle(s) }
        if let r = st.str("repeatMode") { player.setRepeat(RepeatMode(name: r)) }
        if let v = st.double("volume") { player.setVolume(Float(v)) }
    }

    // MARK: controlling another device

    func send(_ command: String, _ params: JSON = [:]) {
        guard let target = activeId else { return }
        var p: JSON = [:]
        for (k, v) in params {
            if let t = v as? Track { p[k] = RealtimeJSON.track(t) }
            else if let ts = v as? [Track] { p[k] = ts.map { RealtimeJSON.track($0) } }
            else { p[k] = v }
        }
        var body: JSON = ["command": command, "deviceId": selfId, "targetDeviceId": target, "params": p]
        for (k, v) in p { body[k] = v }
        post("/api/sync/command", body)

        guard var cur = remoteState else { return }
        let now = Uptime.ms
        switch command {
        case "play": cur.positionMs = cur.position(at: now); cur.isPlaying = true; cur.receivedAt = now
        case "pause": cur.positionMs = cur.position(at: now); cur.isPlaying = false; cur.receivedAt = now
        case "seek": if let ms = params["positionMs"] as? Int { cur.positionMs = ms; cur.receivedAt = now }
        case "setVolume": if let v = params["volume"] as? Double { cur.volume = Float(v) }
        default: break
        }
        remoteState = cur
    }

    func seekRemote(_ ms: Int) {
        let safe = max(0, ms)
        send("seek", ["position": Double(safe) / 1000, "positionMs": safe])
    }

    func transfer(to deviceId: String) {
        guard !token.isEmpty else { return }
        let local = player.snapshot()
        if deviceId == selfId {
            if activeId == selfId { return }
            if activeId == nil && !local.queue.isEmpty {
                claim()
                if !local.isPlaying { player.play() }
                return
            }
            claimPending = false
            post("/api/sync/command", ["command": "transfer", "deviceId": selfId, "targetDeviceId": selfId])
            return
        }
        let sendLocal = activeId == selfId || (activeId == nil && !local.queue.isEmpty)
        var body: JSON = ["command": "transfer", "deviceId": selfId, "targetDeviceId": deviceId]
        if sendLocal { body["state"] = localState(local) }
        post("/api/sync/command", body)
        claimPending = false
        if sendLocal {
            if local.isPlaying { player.pause() }
            remoteState = local.current.map {
                RemotePlaybackState(currentTrack: $0, isPlaying: local.isPlaying, positionMs: local.positionMs,
                                    durationMs: local.durationMs, queue: local.queue, index: local.index,
                                    volume: local.volume, shuffle: local.shuffle, repeatMode: local.repeatMode.name)
            }
        }
        activeId = deviceId
    }

    private func post(_ path: String, _ body: JSON) {
        guard !token.isEmpty, let url = URL(string: CdcClient.base + path) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(API.userAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req).resume()
    }
}
