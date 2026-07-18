import SwiftUI

struct EqualizerView: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var gains: [Float] = Array(repeating: 0, count: 10)

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Toggle(isOn: $settings.eqEnabled) {
                    Text("Enable equalizer").font(SynkFont.sans(15, .medium)).foregroundStyle(Theme.fg)
                }
                .tint(Theme.fg)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Theme.surface1)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(0..<10, id: \.self) { i in
                        VStack(spacing: 6) {
                            Text(gainLabel(gains[i]))
                                .font(SynkFont.sans(9))
                                .foregroundStyle(Theme.faint)
                            VerticalSlider(value: $gains[i], range: -12...12)
                                .frame(height: 180)
                                .disabled(!settings.eqEnabled)
                                .opacity(settings.eqEnabled ? 1 : 0.4)
                                .onChange(of: gains[i]) { _, _ in settings.eqBands = gains }
                            Text(freqLabel(SettingsStore.eqFrequencies[i]))
                                .font(SynkFont.sans(9))
                                .foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
                .background(Theme.surface1)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Eyebrow(text: "Presets").frame(maxWidth: .infinity, alignment: .leading)
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible()), .init(.flexible())], spacing: 8) {
                    ForEach(SettingsStore.eqPresets, id: \.name) { preset in
                        Button {
                            gains = preset.gains
                            settings.eqBands = gains
                        } label: {
                            Text(preset.name)
                                .font(SynkFont.sans(13, .medium))
                                .foregroundStyle(Theme.fg)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Theme.surface2)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .background(Theme.ink)
        .navigationTitle("Equalizer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { gains = settings.eqBands.count == 10 ? settings.eqBands : Array(repeating: 0, count: 10) }
    }

    private func freqLabel(_ hz: Int) -> String { hz >= 1000 ? "\(hz / 1000)k" : "\(hz)" }
    private func gainLabel(_ g: Float) -> String { String(format: "%+.0f", g) }
}

// A vertical slider built on a drag gesture since SwiftUI's Slider is horizontal.
struct VerticalSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let frac = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            ZStack(alignment: .bottom) {
                Capsule().fill(Theme.surface3).frame(width: 4)
                Capsule().fill(Theme.fg).frame(width: 4, height: h * frac)
                Circle().fill(Theme.fg)
                    .frame(width: 16, height: 16)
                    .offset(y: -(h * frac) + 8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let clamped = min(max(0, h - g.location.y), h)
                    let f = Float(clamped / h)
                    value = (range.lowerBound + f * (range.upperBound - range.lowerBound)).rounded()
                }
            )
        }
    }
}
