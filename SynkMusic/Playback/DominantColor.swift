import SwiftUI
import UIKit

// Downsamples the cover to 1x1 and reads the average color, mirroring the
// dominant-color gradient background used by the desktop ImmersiveView.
enum DominantColor {
    private static var cache: [String: Color] = [:]

    static func extract(from urlString: String) async -> Color? {
        if let hit = cache[urlString] { return hit }
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data),
              let cg = image.cgImage else { return nil }

        let ctx = CIContext()
        let ci = CIImage(cgImage: cg)
        let extent = ci.extent
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ci,
            kCIInputExtentKey: CIVector(cgRect: extent),
        ]), let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ctx.render(output, toBitmap: &bitmap, rowBytes: 4,
                   bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                   format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

        // Darken so white text stays readable, like the desktop gradient.
        let r = Double(bitmap[0]) / 255 * 0.7
        let g = Double(bitmap[1]) / 255 * 0.7
        let b = Double(bitmap[2]) / 255 * 0.7
        let color = Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
        cache[urlString] = color
        return color
    }
}
