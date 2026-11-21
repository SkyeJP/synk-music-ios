import SwiftUI
import UIKit
import CryptoKit

private let imageMemory: NSCache<NSURL, UIImage> = {
    let c = NSCache<NSURL, UIImage>()
    c.countLimit = 400
    return c
}()

/// Memory, disk and network image loader with request coalescing. Covers stay on disk
/// so skipping with a bad signal still shows them.
actor ImageCache {
    static let shared = ImageCache()
    private var memory: NSCache<NSURL, UIImage> { imageMemory }
    private var inflight: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 300 << 20)
        c.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: c)
    }()
    private static let maxDiskBytes = 400 << 20
    nonisolated static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private init() {
        Task.detached(priority: .background) { ImageCache.trim() }
    }

    nonisolated func cached(_ url: URL) -> UIImage? { imageMemory.object(forKey: url as NSURL) }

    nonisolated static func file(_ url: URL) -> URL {
        dir.appendingPathComponent(SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined())
    }

    /// Loads these covers into the cache ahead of time.
    nonisolated static func warm(_ urls: [String]) {
        let list = Set(urls.filter { !$0.isEmpty }.compactMap { URL(string: Covers.absolute($0)) })
            .filter { !FileManager.default.fileExists(atPath: file($0).path) }
        guard !list.isEmpty else { return }
        Task.detached(priority: .utility) { for u in list { _ = await ImageCache.shared.image(u) } }
    }

    func image(_ url: URL) async -> UIImage? {
        if let i = memory.object(forKey: url as NSURL) { return i }
        if let t = inflight[url] { return await t.value }
        let session = self.session
        let t = Task<UIImage?, Never> {
            let disk = ImageCache.file(url)
            if let d = try? Data(contentsOf: disk), let img = UIImage(data: d) {
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: disk.path)
                return img.preparingForDisplay() ?? img
            }
            guard let res = try? await session.data(from: url), (res.1 as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                  let img = UIImage(data: res.0) else { return nil }
            try? res.0.write(to: disk, options: .atomic)
            return img.preparingForDisplay() ?? img
        }
        inflight[url] = t
        var img = await t.value
        inflight[url] = nil
        if img == nil, let small = URL(string: url.absoluteString.replacingOccurrences(of: "&size=1400", with: "")), small != url {
            img = await image(small)
        }
        if let img { memory.setObject(img, forKey: url as NSURL) }
        return img
    }

    private nonisolated static func trim() {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { return }
        var items = files.compactMap { u -> (URL, Int, Date)? in
            guard let v = try? u.resourceValues(forKeys: Set(keys)) else { return nil }
            return (u, v.fileSize ?? 0, v.contentModificationDate ?? .distantPast)
        }
        var total = items.reduce(0) { $0 + $1.1 }
        items.sort { $0.2 < $1.2 }
        for (u, size, _) in items where total > maxDiskBytes {
            try? fm.removeItem(at: u)
            total -= size
        }
    }
}

struct RemoteImage: View {
    let url: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .task(id: url) {
            guard let u = URL(string: Covers.absolute(url)), !url.isEmpty else { image = nil; return }
            if let c = ImageCache.shared.cached(u) { image = c; return }
            image = nil
            let loaded = await ImageCache.shared.image(u)
            if !Task.isCancelled { withAnimation(.easeOut(duration: 0.2)) { image = loaded } }
        }
    }
}

/// Square artwork with a note when there is none.
struct Artwork: View {
    let url: String
    var radius: CGFloat = 10
    var round = false

    var body: some View {
        ZStack {
            Theme.surface3
            SynkIcon(SynkIcons.musicNote, size: 26, tint: Theme.faint)
            if !url.isEmpty { RemoteImage(url: url) }
        }
        .clipShape(round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous)))
    }
}

// MARK: artwork colour

enum ArtColor {
    private static var cache: [String: UIColor] = [:]

    /// A dark, saturated colour from the artwork, like Palette's dark vibrant swatch.
    static func dominant(_ url: String) async -> UIColor? {
        if let c = cache[url] { return c }
        guard let u = URL(string: Covers.absolute(url)), let img = await ImageCache.shared.image(u), let cg = img.cgImage else { return nil }
        let c = await Task.detached(priority: .utility) { ArtColor.extract(cg) }.value
        if let c { cache[url] = c }
        return c
    }

    private static func extract(_ cg: CGImage) -> UIColor? {
        let w = 32, h = 32
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        if !drawn { return nil }
        // Hue buckets weighted by saturation, so a vivid colour wins over grey.
        var weight = [Double](repeating: 0, count: 36)
        var sums = [(Double, Double, Double)](repeating: (0, 0, 0), count: 36)
        var fallback = (0.0, 0.0, 0.0)
        for i in stride(from: 0, to: px.count, by: 4) {
            let r = Double(px[i]) / 255, g = Double(px[i + 1]) / 255, b = Double(px[i + 2]) / 255
            fallback.0 += r; fallback.1 += g; fallback.2 += b
            let mx = max(r, g, b), mn = min(r, g, b)
            let s = mx == 0 ? 0 : (mx - mn) / mx
            if s < 0.2 || mx < 0.12 { continue }
            var hue = 0.0
            let d = mx - mn
            if mx == r { hue = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { hue = (b - r) / d + 2 }
            else { hue = (r - g) / d + 4 }
            hue = hue * 60
            if hue < 0 { hue += 360 }
            let k = min(35, Int(hue / 10))
            let wgt = s * (0.4 + 0.6 * mx)
            weight[k] += wgt
            sums[k].0 += r * wgt; sums[k].1 += g * wgt; sums[k].2 += b * wgt
        }
        let n = Double(w * h)
        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > n * 0.02 else {
            return UIColor(red: fallback.0 / n, green: fallback.1 / n, blue: fallback.2 / n, alpha: 1)
        }
        let s = sums[best], wsum = weight[best]
        return UIColor(red: s.0 / wsum, green: s.1 / wsum, blue: s.2 / wsum, alpha: 1)
    }

    /// The colour at a fixed brightness with saturation capped, for panels.
    static func panel(_ c: UIColor?, value: CGFloat) -> Color {
        guard let c else { return Color(hex: 0x2A2A2A) }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: min(s, 0.62), brightness: value)
    }
}

/// The artwork's panel colour, animated when it changes.
struct ArtTint: ViewModifier {
    let url: String
    let value: CGFloat
    @Binding var color: Color

    func body(content: Content) -> some View {
        content.task(id: url) {
            let c = await ArtColor.dominant(url)
            withAnimation(.easeInOut(duration: 0.6)) { color = ArtColor.panel(c, value: value) }
        }
    }
}

extension View {
    func artTint(_ url: String, value: CGFloat, into color: Binding<Color>) -> some View {
        modifier(ArtTint(url: url, value: value, color: color))
    }
}
