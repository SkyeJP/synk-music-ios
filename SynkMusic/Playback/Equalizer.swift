import Foundation
import AVFoundation
import MediaToolbox

/// 10-band graphic EQ plus the device tuning filters, as cascaded RBJ biquads.
/// The same design and maths as Android's EqualizerAudioProcessor; it runs in an
/// MTAudioProcessingTap on every player item.
final class Equalizer {
    static let shared = Equalizer()
    static let freqs: [Double] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    struct Tune { let type: String; let fc: Double; let gain: Double; let q: Double }

    private let lock = NSLock()
    private(set) var version = 0
    private var enabled = false
    private var gains = [Double](repeating: 0, count: 10)
    private var tune: [Tune] = []
    private var preampDb = 0.0

    func setBands(enabled: Bool, gains: [Double]) {
        lock.lock()
        self.enabled = enabled
        self.gains = (0..<10).map { $0 < gains.count ? gains[$0] : 0 }
        version += 1
        lock.unlock()
    }

    func setTuning(_ filters: [Tune], preamp: Double) {
        lock.lock()
        tune = filters
        preampDb = preamp
        version += 1
        lock.unlock()
    }

    /// Filter chain for one sample rate and channel count.
    func build(sampleRate sr: Double, channels: Int) -> Chain {
        lock.lock(); defer { lock.unlock() }
        let flat = gains.allSatisfy { abs($0) < 0.05 }
        let bands: [Coeffs] = (enabled && !flat) ? Equalizer.freqs.enumerated().map { peaking($0.element, gains[$0.offset], 1, sr) } : []
        let tunes: [Coeffs] = tune.filter { $0.fc > 0 && $0.fc < sr * 0.49 && $0.q > 0 }.map {
            switch $0.type {
            case "LSC": return shelf(true, $0.fc, $0.gain, $0.q, sr)
            case "HSC": return shelf(false, $0.fc, $0.gain, $0.q, sr)
            default: return peaking($0.fc, $0.gain, $0.q, sr)
            }
        }
        let pre = tunes.isEmpty ? 1.0 : pow(10, min(6, max(-24, preampDb)) / 20)
        return Chain(coeffs: tunes + bands, preamp: Float(pre), channels: channels, version: version)
    }

    struct Coeffs { var b0, b1, b2, a1, a2: Double }

    private func peaking(_ f0: Double, _ gainDb: Double, _ q: Double, _ sr: Double) -> Coeffs {
        let a = pow(10, gainDb / 40), w0 = 2 * Double.pi * f0 / sr, cw = cos(w0), alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha / a
        return Coeffs(b0: (1 + alpha * a) / a0, b1: -2 * cw / a0, b2: (1 - alpha * a) / a0, a1: -2 * cw / a0, a2: (1 - alpha / a) / a0)
    }

    private func shelf(_ low: Bool, _ f0: Double, _ gainDb: Double, _ q: Double, _ sr: Double) -> Coeffs {
        let a = pow(10, gainDb / 40), w0 = 2 * Double.pi * f0 / sr, cw = cos(w0)
        let s = 2 * sqrt(a) * sin(w0) / (2 * q)
        let b0, b1, b2, a0, a1, a2: Double
        if low {
            b0 = a * ((a + 1) - (a - 1) * cw + s); b1 = 2 * a * ((a - 1) - (a + 1) * cw); b2 = a * ((a + 1) - (a - 1) * cw - s)
            a0 = (a + 1) + (a - 1) * cw + s; a1 = -2 * ((a - 1) + (a + 1) * cw); a2 = (a + 1) + (a - 1) * cw - s
        } else {
            b0 = a * ((a + 1) + (a - 1) * cw + s); b1 = -2 * a * ((a - 1) + (a + 1) * cw); b2 = a * ((a + 1) + (a - 1) * cw - s)
            a0 = (a + 1) - (a - 1) * cw + s; a1 = 2 * ((a - 1) - (a + 1) * cw); a2 = (a + 1) - (a - 1) * cw - s
        }
        return Coeffs(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    /// Filters plus per-channel state, owned by one tap. No allocation while processing.
    final class Chain {
        let coeffs: [Coeffs]
        let preamp: Float
        let version: Int
        private let channels: Int
        private let z1: UnsafeMutablePointer<Double>
        private let z2: UnsafeMutablePointer<Double>

        init(coeffs: [Coeffs], preamp: Float, channels: Int, version: Int) {
            self.coeffs = coeffs; self.preamp = preamp; self.version = version
            self.channels = max(1, channels)
            let n = max(1, coeffs.count * self.channels)
            z1 = .allocate(capacity: n); z1.initialize(repeating: 0, count: n)
            z2 = .allocate(capacity: n); z2.initialize(repeating: 0, count: n)
        }

        deinit { z1.deallocate(); z2.deallocate() }

        var isEmpty: Bool { coeffs.isEmpty }

        func process(_ buf: UnsafeMutablePointer<Float>, frames: Int, channel: Int, stride: Int) {
            if coeffs.isEmpty || channel >= channels { return }
            let n = coeffs.count
            let s1 = z1 + channel * n, s2 = z2 + channel * n
            coeffs.withUnsafeBufferPointer { c in
                var i = 0
                for _ in 0..<frames {
                    var x = Double(buf[i] * preamp)
                    for k in 0..<n {
                        let f = c[k]
                        let y = f.b0 * x + s1[k]
                        s1[k] = f.b1 * x - f.a1 * y + s2[k]
                        s2[k] = f.b2 * x - f.a2 * y
                        x = y
                    }
                    buf[i] = Float(max(-1, min(1, x)))
                    i += stride
                }
            }
        }
    }
}

// MARK: processing tap

private final class TapState {
    var sampleRate: Double = 44100
    var channels = 2
    var interleaved = false
    var isFloat = true
    var chain: Equalizer.Chain?
}

enum EQTap {
    /// An audio mix that runs the equaliser on the item's first audio track.
    static func audioMix(for track: AVAssetTrack) -> AVAudioMix? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: nil,
            init: { _, _, storageOut in
                storageOut.pointee = Unmanaged.passRetained(TapState()).toOpaque()
            },
            finalize: { tap in
                Unmanaged<TapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                let st = Unmanaged<TapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                let asbd = format.pointee
                st.sampleRate = asbd.mSampleRate
                st.channels = Int(asbd.mChannelsPerFrame)
                st.interleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
                st.isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 && asbd.mBitsPerChannel == 32
                st.chain = nil
            },
            unprepare: { _ in },
            process: { tap, frames, _, bufferList, framesOut, flagsOut in
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, bufferList, flagsOut, nil, framesOut) == noErr else { return }
                let st = Unmanaged<TapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                guard st.isFloat else { return }
                let eq = Equalizer.shared
                if st.chain == nil || st.chain!.version != eq.version {
                    st.chain = eq.build(sampleRate: st.sampleRate, channels: st.channels)
                }
                guard let chain = st.chain, !chain.isEmpty else { return }
                let n = Int(framesOut.pointee)
                let abl = UnsafeMutableAudioBufferListPointer(bufferList)
                if st.interleaved {
                    guard let first = abl.first, let data = first.mData else { return }
                    let p = data.assumingMemoryBound(to: Float.self)
                    let ch = Int(first.mNumberChannels)
                    for c in 0..<ch { chain.process(p + c, frames: n, channel: c, stride: ch) }
                } else {
                    for (c, b) in abl.enumerated() {
                        guard let data = b.mData else { continue }
                        chain.process(data.assumingMemoryBound(to: Float.self), frames: n, channel: c, stride: 1)
                    }
                }
            }
        )
        var tapOut: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tapOut) == noErr,
              let tap = tapOut else { return nil }
        let params = AVMutableAudioMixInputParameters(track: track)
        params.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        return mix
    }
}
