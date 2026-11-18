import SwiftUI
import UIKit
import CoreText

enum Theme {
    static let ink = Color(hex: 0x000000)
    static let base = Color(hex: 0x060606)
    static let surface1 = Color(hex: 0x0E0E0E)
    static let surface2 = Color(hex: 0x161616)
    static let surface3 = Color(hex: 0x202020)
    static let elevated = Color(hex: 0x282828)
    static let line = Color.white.opacity(0.08)
    static let lineStrong = Color.white.opacity(0.16)
    static let hairline = Color.white.opacity(0.14)
    static let fg = Color.white
    static let muted = Color(hex: 0xB3B3B3)
    static let faint = Color(hex: 0x8A8A8A)
    static let bone = Color(hex: 0xECE9E4)
    static let danger = Color(hex: 0xEF6B6B)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

/// Host Grotesk for headings, Figtree for everything else, both variable fonts
/// set to an exact weight like the Android app.
enum SynkFont {
    private static var cache: [String: UIFont] = [:]
    private static let wght = 0x77676874

    static func register() {
        for name in ["HostGrotesk", "Figtree"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    static func ui(_ family: String, _ size: CGFloat, _ weight: Int) -> UIFont {
        let key = "\(family)|\(size)|\(weight)"
        if let f = cache[key] { return f }
        let attrs: [UIFontDescriptor.AttributeName: Any] = [
            .family: family,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [wght: weight],
        ]
        let f = UIFont(descriptor: UIFontDescriptor(fontAttributes: attrs), size: size)
        cache[key] = f
        return f
    }

    static func display(_ size: CGFloat, _ weight: Int = 700) -> Font { Font(ui("Host Grotesk", size, weight)) }
    static func sans(_ size: CGFloat, _ weight: Int = 400) -> Font { Font(ui("Figtree", size, weight)) }
}

extension View {
    func font(sans size: CGFloat, _ weight: Int = 400) -> some View { font(SynkFont.sans(size, weight)) }
    func font(display size: CGFloat, _ weight: Int = 700) -> some View { font(SynkFont.display(size, weight)) }
}
