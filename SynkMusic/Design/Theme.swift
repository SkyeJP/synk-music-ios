import SwiftUI

enum Theme {
    static let ink       = Color(hex: 0x000000)
    static let base      = Color(hex: 0x060606)
    static let surface1  = Color(hex: 0x0E0E0E)
    static let surface2  = Color(hex: 0x161616)
    static let surface3  = Color(hex: 0x202020)
    static let elevated  = Color(hex: 0x282828)
    static let fg        = Color(hex: 0xFFFFFF)
    static let muted     = Color(hex: 0xB3B3B3)
    static let faint     = Color(hex: 0x6F6F6F)
    static let line      = Color.white.opacity(0.08)
    static let lineStrong = Color.white.opacity(0.16)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    init?(cssHex: String?) {
        guard var s = cssHex else { return nil }
        s = s.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard let v = UInt32(s, radix: 16), s.count == 6 else { return nil }
        self.init(hex: v)
    }
}

// Host Grotesk (UI) + Figtree (lyrics), bundled as variable TTFs and registered
// at launch (see FontRegistrar). Referenced by family name so SwiftUI can apply
// weights; falls back to the system font if registration fails.
enum SynkFont {
    static let sansFamily = "Host Grotesk"
    static let lyricsFamily = "Figtree"

    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(sansFamily, size: size).weight(weight)
    }
    static func lyrics(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .custom(lyricsFamily, size: size).weight(weight)
    }
}

// Registers the bundled variable fonts with CoreText at process start so the
// `.custom(family:)` lookups resolve. Idempotent.
enum FontRegistrar {
    private static var done = false
    static func register() {
        guard !done else { return }
        done = true
        for name in ["HostGrotesk", "Figtree"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Text {
    func synk(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Text {
        self.font(SynkFont.sans(size, weight))
    }
}

// Eyebrow / label style used across the app (uppercase, tracked).
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.muted
    var body: some View {
        Text(text.uppercased())
            .font(SynkFont.sans(11, .bold))
            .tracking(1.2)
            .foregroundStyle(color)
    }
}
