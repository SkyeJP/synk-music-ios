import SwiftUI
import UIKit

private let imageMemory: NSCache<NSURL, UIImage> = {
    let c = NSCache<NSURL, UIImage>()
    c.countLimit = 400
    return c
}()

/// Memory plus URLCache backed image loader with request coalescing.
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

    nonisolated func cached(_ url: URL) -> UIImage? { imageMemory.object(forKey: url as NSURL) }

    func image(_ url: URL) async -> UIImage? {
        if let i = memory.object(forKey: url as NSURL) { return i }
        if let t = inflight[url] { return await t.value }
        let session = self.session
        let t = Task<UIImage?, Never> {
            guard let res = try? await session.data(from: url), let img = UIImage(data: res.0) else { return nil }
            return img.preparingForDisplay() ?? img
        }
        inflight[url] = t
        let img = await t.value
        inflight[url] = nil
        if let img { memory.setObject(img, forKey: url as NSURL) }
        return img
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
