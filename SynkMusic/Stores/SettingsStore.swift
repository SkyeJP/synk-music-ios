import Foundation
import SwiftUI

// Local prefs mirroring the Android SettingsStore (DataStore). EQ bands persist
// as a comma-joined string of 10 gains.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @AppStorage("audioQuality") var audioQuality: String = "default"
    @AppStorage("autoplay") var autoplay: Bool = true
    @AppStorage("gapless") var gapless: Bool = true
    @AppStorage("eqEnabled") var eqEnabled: Bool = false
    @AppStorage("eqBands") private var eqBandsRaw: String = "0,0,0,0,0,0,0,0,0,0"

    var eqBands: [Float] {
        get { eqBandsRaw.split(separator: ",").map { Float($0) ?? 0 } }
        set { eqBandsRaw = newValue.map { String($0) }.joined(separator: ",") }
    }

    static let qualityOptions: [(id: String, label: String)] = [
        ("default", "Default"),
        ("128", "Standard (128)"),
        ("320", "High (320)"),
        ("lossless", "Lossless"),
    ]

    static let eqFrequencies: [Int] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    static let eqPresets: [(name: String, gains: [Float])] = [
        ("Flat", Array(repeating: 0, count: 10)),
        ("Bass", [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
        ("Treble", [0, 0, 0, 0, 0, 2, 3, 4, 5, 6]),
        ("Vocal", [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1]),
        ("Rock", [4, 3, 2, 0, -1, 0, 2, 3, 4, 4]),
        ("Pop", [-1, 0, 2, 4, 4, 3, 1, 0, -1, -2]),
        ("Jazz", [3, 2, 1, 2, -1, -1, 0, 1, 2, 3]),
        ("Classical", [4, 3, 2, 0, 0, 0, -1, -1, 2, 3]),
        ("Electronic", [5, 4, 1, 0, -2, 2, 1, 2, 4, 5]),
        ("Acoustic", [4, 3, 2, 1, 2, 2, 3, 3, 2, 1]),
    ]
}
