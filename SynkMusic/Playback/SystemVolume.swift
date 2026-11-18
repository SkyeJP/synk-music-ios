import AVFoundation
import MediaPlayer
import SwiftUI

/// The phone's own volume. iOS only lets apps change it through the system
/// volume view, so a hidden one sits in the player and our slider drives it.
@MainActor
final class SystemVolume: ObservableObject {
    static let shared = SystemVolume()

    @Published private(set) var level: Float = AVAudioSession.sharedInstance().outputVolume
    let view = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 120, height: 40))
    private var observer: NSKeyValueObservation?

    private init() {
        observer = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            let v = change.newValue ?? 0
            Task { @MainActor in self?.level = v }
        }
    }

    func set(_ v: Float) {
        let clamped = min(1, max(0, v))
        level = clamped
        guard let slider = view.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.setValue(clamped, animated: false)
        slider.sendActions(for: .valueChanged)
    }
}

/// Puts the hidden system volume view on screen, which also stops the volume
/// HUD covering the player when the buttons are pressed.
struct SystemVolumeHost: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let host = UIView(frame: .zero)
        host.isUserInteractionEnabled = false
        host.alpha = 0.01
        let v = SystemVolume.shared.view
        v.removeFromSuperview()
        host.addSubview(v)
        return host
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
