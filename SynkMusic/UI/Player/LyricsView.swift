import SwiftUI
import UIKit

// Same tuning as the Android and desktop apps.
private let dimBase: Double = 0.30
private let heldMs = 650
private let dotsMinGap = 3000
private let anchor: CGFloat = 0.28
private let soft: CGFloat = 12

private enum LyricItem: Equatable {
    case line(LyricLine, start: Int, end: Int, bgStart: Int)
    case dots(start: Int, end: Int)

    var start: Int {
        switch self {
        case .line(_, let s, _, _): return s
        case .dots(let s, _): return s
        }
    }
}

private func buildItems(_ lines: [LyricLine]) -> [LyricItem] {
    var out: [LyricItem] = []
    var prevEnd = 0
    for (i, l) in lines.enumerated() {
        if l.text.trimmingCharacters(in: .whitespaces).isEmpty && (l.words ?? []).isEmpty { continue }
        let next = i + 1 < lines.count ? lines[i + 1].time : nil
        let end = l.end ?? min(next ?? (l.time + 4000), l.time + 6000)
        if l.time - prevEnd >= dotsMinGap { out.append(.dots(start: prevEnd, end: l.time)) }
        let bg = l.bgWords ?? []
        let bgEnd = bg.last.map { $0.end ?? ($0.time + 300) } ?? end
        let bgStart = bg.first?.time ?? l.time
        out.append(.line(l, start: l.time, end: max(end, bgEnd), bgStart: bgStart))
        prevEnd = max(end, bgEnd)
    }
    return out
}

private func ease(_ t: Double) -> Double {
    let x = min(1, max(0, t))
    return x * x * (3 - 2 * x)
}

/// When letter k of `count` in word w is sung, in ms.
private func letterWindow(_ words: [LyricWord], _ w: Int, _ k: Int, _ count: Int, _ lineEnd: Int?) -> (Double, Double) {
    let word = words[w]
    if let chars = word.chars, !chars.isEmpty {
        let i = min(chars.count - 1, max(0, count == chars.count ? k : k * chars.count / max(1, count)))
        let c = chars[i]
        let s = Double(c.first ?? word.time)
        let e = max(s + 30, Double(c.count > 1 ? c[1] : Int(s)))
        return (s, e)
    }
    let ws = word.time
    let we: Int
    if let e = word.end, e > word.time { we = e }
    else if w + 1 < words.count { we = words[w + 1].time }
    else if let le = lineEnd, le > word.time { we = min(ws + 1500, le) }
    else { we = ws + 350 }
    let dur = Double(max(120, we - ws))
    let f0 = Double(k) / Double(count), f1 = Double(k + 1) / Double(count)
    let start = Double(ws) + f0 * dur * 0.85
    return (start, start + max(70, Double(ws) + f1 * dur - start))
}

private func wordEnd(_ words: [LyricWord], _ w: Int, _ lineEnd: Int?, _ lineTime: Int) -> Int {
    let word = words[w]
    if let last = word.chars?.last, last.count > 1, last[1] > word.time { return last[1] }
    if let e = word.end, e > word.time { return e }
    if w + 1 < words.count { return words[w + 1].time }
    return min(word.time + 2000, (lineEnd ?? (lineTime + 4000)) - 100)
}

@MainActor
private final class LyricsLoader: ObservableObject {
    @Published var lyrics: Lyrics?
    @Published var failed = false
    private var loadedFor = ""

    func load(_ t: Track) async {
        if loadedFor == t.hash { return }
        loadedFor = t.hash
        lyrics = nil
        failed = false
        if let l = try? await API.shared.lyrics(t) { lyrics = l } else { failed = true }
    }
}

struct LyricsView: View {
    let track: Track
    var onSeek: ((Int) -> Void)?
    var textSize: CGFloat = 30
    @StateObject private var loader = LyricsLoader()
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var cdc: CdcClient

    var body: some View {
        Group {
            if let l = loader.lyrics, !l.lyrics.isEmpty {
                LyricsContent(lines: l.lyrics, synced: l.synced, playing: Playback.state().isPlaying, onSeek: onSeek, textSize: textSize)
            } else if loader.lyrics != nil || loader.failed {
                note("No lyrics for this song")
            } else {
                note("Finding lyrics")
            }
        }
        .task(id: track.hash) { await loader.load(track) }
    }

    private func note(_ s: String) -> some View {
        Text(s).font(sans: 16).foregroundStyle(Theme.faint).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Lyrics in a sheet, for the player's lyrics button when opened from elsewhere.
struct LyricsSheet: View {
    let track: Track
    var body: some View {
        LyricsView(track: track, onSeek: { Playback.seek($0) }).padding(.top, 24)
    }
}

private struct HeightsKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, n in n }
    }
}

@MainActor private func livePosition() -> Int { Playback.isRemote ? Playback.positionMs().0 : PlayerController.shared.positionMs }

struct LyricsContent: View {
    let lines: [LyricLine]
    let synced: Bool
    let playing: Bool
    var onSeek: ((Int) -> Void)?
    var textSize: CGFloat = 30
    @State private var items: [LyricItem] = []
    @State private var heights: [Int: CGFloat] = [:]
    @State private var viewport: CGFloat = 0
    @State private var manual: CGFloat = 0
    @State private var dragStart: CGFloat = 0
    @State private var frozen: CGFloat?
    @State private var dragging = false
    @State private var released = Date()

    var body: some View {
        Group {
            if synced {
                TimelineView(.animation(minimumInterval: nil, paused: !playing)) { _ in
                    let now = livePosition()
                    content(now: now)
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            if case .line(let l, _, _, _) = item {
                                Text(l.text).font(SynkFont.sans(textSize, 700)).foregroundStyle(Color.white.opacity(0.8))
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 40)
                }
            }
        }
        .mask(edgeFade)
        .onAppear { items = buildItems(lines) }
        .onChange(of: lines) { _, l in items = buildItems(l); heights = [:] }
    }

    private func content(now: Int) -> some View {
        let active = max(0, items.lastIndex { $0.start <= now } ?? 0)
        var above: CGFloat = 0
        for i in 0..<active { above += heights[i] ?? 0 }
        let target = viewport * anchor - above
        let base = frozen ?? target
        let total = heights.values.reduce(0, +)
        let free = frozen != nil
        return GeometryReader { g in
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    let d = i - active
                    let dist = Double(abs(d))
                    let near = abs(d) <= 1
                    itemView(item, index: i, active: i == active, now: (near || isDots(item)) ? now : (d < 0 ? Int.max / 4 : -1), dist: dist)
                        .background(GeometryReader { h in Color.clear.preference(key: HeightsKey.self, value: [i: h.size.height]) })
                        .blur(radius: !synced || free ? 0 : abs(d) < 12 ? min(4, max(0, (dist - 1) * 1.2)) : 4)
                        .animation(.easeInOut(duration: 0.4), value: active)
                }
            }
            .offset(y: base + manual)
            .animation(.spring(response: 0.55, dampingFraction: 0.9), value: active)
            .animation(.easeInOut(duration: 0.3), value: free)
            .padding(.horizontal, 24)
            .frame(width: g.size.width, alignment: .topLeading)
            .onAppear { viewport = g.size.height }
            .onChange(of: g.size.height) { _, h in viewport = h }
        }
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { v in
                    if !dragging {
                        dragging = true
                        if frozen == nil { frozen = target; manual = 0 }
                        dragStart = manual
                    }
                    manual = clampManual(dragStart + v.translation.height, base: frozen ?? target, total: total)
                }
                .onEnded { v in
                    dragging = false
                    let end = clampManual(dragStart + v.predictedEndTranslation.height, base: frozen ?? target, total: total)
                    withAnimation(.easeOut(duration: 0.45)) { manual = end }
                    released = Date()
                }
        )
        .task(id: released) {
            guard frozen != nil else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, !dragging else { return }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) { frozen = nil; manual = 0 }
        }
        .onPreferenceChange(HeightsKey.self) { v in MainActor.assumeIsolated { heights = v } }
    }

    private func clampManual(_ m: CGFloat, base: CGFloat, total: CGFloat) -> CGFloat {
        let top = viewport * anchor
        let lo = top - total - base
        let hi = top + viewport * 0.4 - base
        return min(max(m, min(lo, hi)), hi)
    }

    private func isDots(_ item: LyricItem) -> Bool {
        if case .dots = item { return true }
        return false
    }

    @ViewBuilder
    private func itemView(_ item: LyricItem, index: Int, active: Bool, now: Int, dist: Double) -> some View {
        switch item {
        case .dots(let s, let e):
            DotsView(start: s, end: e, now: now)
        case .line(let l, _, let end, let bgStart):
            LineView(line: l, end: end, bgStart: bgStart, synced: synced, isActive: active, now: now,
                     dim: max(0.14, dimBase - max(0, dist - 1) * 0.02), size: textSize,
                     onSeek: onSeek.map { seek in { (ms: Int) -> Void in withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) { frozen = nil; manual = 0 }; seek(ms) } })
                .equatable()
                .padding(.bottom, 22)
        }
    }

    private var edgeFade: some View {
        var stops: [Gradient.Stop] = []
        for k in 0...6 { let t = Double(k) / 6; stops.append(.init(color: .white.opacity(ease(t)), location: 0.16 * t)) }
        for k in stride(from: 6, through: 0, by: -1) { let t = Double(k) / 6; stops.append(.init(color: .white.opacity(ease(t)), location: 1 - 0.22 * t)) }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }
}

private struct LineView: View, Equatable {
    let line: LyricLine
    let end: Int
    let bgStart: Int
    let synced: Bool
    let isActive: Bool
    let now: Int
    let dim: Double
    let size: CGFloat
    var onSeek: ((Int) -> Void)?

    static func == (a: LineView, b: LineView) -> Bool {
        a.line == b.line && a.end == b.end && a.synced == b.synced && a.isActive == b.isActive &&
            a.now == b.now && a.dim == b.dim && a.size == b.size
    }

    var body: some View {
        let sung = now >= end
        let lit: Double = !synced ? 0 : sung ? 1 - ease(Double(now - end) / 450) : isActive ? 1 : 0
        VStack(alignment: .leading, spacing: 0) {
            if let words = line.words, !words.isEmpty {
                WordFlow(words: words, lineEnd: line.end, now: now, dim: dim, lit: lit, size: size)
            } else {
                let a = !synced ? 0.8 : dim + (1 - dim) * lit
                Text(line.text).font(SynkFont.sans(size, 700)).foregroundStyle(Color.white.opacity(a))
                    .lineSpacing(size * 0.22)
            }
            if let bg = line.bgWords, !bg.isEmpty {
                let vis = ease(Double(now - bgStart + 350) / 350) * (1 - ease(Double(now - end) / 450))
                WordFlow(words: bg, lineEnd: line.end, now: now, dim: dim, lit: lit * 0.85, size: size * 0.66)
                    .padding(.top, 6)
                    .opacity(vis)
                    .collapse(vis)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { if synced { onSeek?(line.time) } }
    }
}

private struct WordFlow: View {
    let words: [LyricWord]
    let lineEnd: Int?
    let now: Int
    let dim: Double
    let lit: Double
    let size: CGFloat

    var body: some View {
        let layout = FlowLayout(spacing: size * 0.26, lineSpacing: size * 0.22)
        layout {
            ForEach(words.indices, id: \.self) { w in
                WordView(words: words, index: w, lineEnd: lineEnd, now: now, dim: dim, lit: lit, size: size)
            }
        }
    }
}

/// One word: dim base, lit part swept left to right with a soft edge, lifted and glowing while held.
private struct WordView: View {
    let words: [LyricWord]
    let index: Int
    let lineEnd: Int?
    let now: Int
    let dim: Double
    let lit: Double
    let size: CGFloat

    var body: some View {
        let word = words[index]
        let text = word.word
        let start = word.time
        let end = wordEnd(words, index, lineEnd, word.time)
        let held = end - start >= heldMs
        let lift: Double = (held && lit > 0 && now >= start && now < end + 250)
            ? min(ease(Double(now - start) / 260), 1 - ease(Double(now - end) / 250)) : 0
        let font = SynkFont.ui("Figtree", size, 700)
        let width = max(1, WordMetrics.width(text, font))
        let litA = dim + (1 - dim) * lit
        let style: AnyShapeStyle = {
            if lit <= 0 || now < start { return AnyShapeStyle(Color.white.opacity(dim)) }
            var edge: CGFloat = 0
            if now >= end {
                edge = width + soft * 2
            } else {
                let n = max(1, text.count)
                for k in 0..<n {
                    let (s, e) = letterWindow(words, index, k, n, lineEnd)
                    let left = WordMetrics.prefix(text, k, font)
                    let right = WordMetrics.prefix(text, k + 1, font)
                    if Double(now) >= e { edge = right }
                    else if Double(now) > s { edge = left + (right - left) * CGFloat((Double(now) - s) / (e - s)); break }
                    else { break }
                }
            }
            let a = min(1, max(0, (edge - soft) / width)), b = min(1, max(0, (edge + soft) / width))
            if b <= a { return AnyShapeStyle(Color.white.opacity(edge > 0 ? litA : dim)) }
            return AnyShapeStyle(LinearGradient(stops: [
                .init(color: .white.opacity(litA), location: 0), .init(color: .white.opacity(litA), location: a),
                .init(color: .white.opacity(dim), location: b), .init(color: .white.opacity(dim), location: 1),
            ], startPoint: .leading, endPoint: .trailing))
        }()
        Text(text)
            .font(Font(font))
            .foregroundStyle(style)
            .shadow(color: .white.opacity(0.55 * lift), radius: lift > 0 ? 9 : 0)
            .offset(y: -2.5 * lift)
            .fixedSize()
    }
}

/// Prefix widths of words, measured once with the real font.
@MainActor
private enum WordMetrics {
    private static var cache: [String: [CGFloat]] = [:]

    static func widths(_ s: String, _ f: UIFont) -> [CGFloat] {
        let key = "\(f.pointSize)|\(s)"
        if let w = cache[key] { return w }
        var out: [CGFloat] = [0]
        var prefix = ""
        for ch in s {
            prefix.append(ch)
            out.append((prefix as NSString).size(withAttributes: [.font: f]).width)
        }
        if cache.count > 4000 { cache.removeAll() }
        cache[key] = out
        return out
    }

    static func prefix(_ s: String, _ k: Int, _ f: UIFont) -> CGFloat {
        let w = widths(s, f)
        return w[min(max(0, k), w.count - 1)]
    }

    static func width(_ s: String, _ f: UIFont) -> CGFloat { widths(s, f).last ?? 0 }
}

/// Three dots that light up across a gap, breathe, and shrink before the next line.
private struct DotsView: View {
    let start: Int
    let end: Int
    let now: Int

    var body: some View {
        let show: Double = (now >= start - 300 && now < end) ? ease(Double(now - start + 300) / 300) * (1 - ease(Double(now - (end - 350)) / 350)) : 0
        let total = Double(max(1, end - start))
        let t = min(1, max(0, Double(now - start) / total))
        let breathe = 1 + 0.08 * sin(Double(now) / 1000 * 6.283 * 0.8)
        VStack(alignment: .leading, spacing: 0) {
            Canvas { ctx, sz in
                for k in 0..<3 {
                    let litK = min(1, max(0, t * 3 - Double(k)))
                    let r = CGFloat(6 * breathe * show)
                    if r <= 0.1 { continue }
                    let c = CGPoint(x: 8 + CGFloat(k) * 22, y: sz.height / 2)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                             with: .color(.white.opacity((dimBase + (1 - dimBase) * litK) * show)))
                }
            }
            .frame(width: 80, height: 36)
            Spacer().frame(height: 22)
        }
        .collapse(show)
    }
}

/// Wraps words like text, left aligned.
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { y += rowH + lineSpacing; x = 0; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { y += rowH + lineSpacing; x = bounds.minX; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

/// Takes `f` of its content's height (0 hides it and takes no space).
private struct Collapse: Layout {
    var f: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let v = subviews.first else { return .zero }
        let s = v.sizeThatFits(proposal)
        return CGSize(width: s.width, height: s.height * min(1, max(0, f)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: proposal)
    }
}

private extension View {
    func collapse(_ f: Double) -> some View {
        let layout = Collapse(f: CGFloat(f))
        return layout { self }.clipped()
    }
}
