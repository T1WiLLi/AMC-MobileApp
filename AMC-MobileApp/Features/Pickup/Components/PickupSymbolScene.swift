import SwiftUI

/// Petite scène de SF Symbols (pas de photo) : un grand symbole dans un disque teinté,
/// entouré de pastilles satellites. Sert d'en-tête à la Cueillette et d'illustration aux états vides et de succès.
///
///     PickupSymbolScene(main: "qrcode.viewfinder", satellites: ["basket.fill", "house.fill", "clock.fill"])
///
/// Le symbole principal rebondit une fois à l'apparition (rien sous Reduce Motion). Décoratif pour VoiceOver.
struct PickupSymbolScene: View {
    let main: String
    var satellites: [String] = []
    var tint: Color = .grenier
    /// Diamètre du disque central, mis à l'échelle avec la taille du texte.
    var diameter: CGFloat = 96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.14))
            Circle()
                .strokeBorder(tint.opacity(0.22), lineWidth: 1.5)
                .padding(diameter * 0.1)
            Image(systemName: main)
                .font(.system(size: diameter * 0.4, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .symbolEffect(.bounce.up.byLayer, value: appeared)
            ForEach(Array(satellites.prefix(4).enumerated()), id: \.offset) { index, symbol in
                satellite(symbol)
                    .offset(offset(for: index, count: min(satellites.count, 4)))
            }
        }
        .frame(width: diameter, height: diameter)
        .padding(satellites.isEmpty ? 0 : diameter * 0.14)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            appeared = true
        }
    }

    private func satellite(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: diameter * 0.15, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: diameter * 0.32, height: diameter * 0.32)
            .background(Color.surface, in: .circle)
            .overlay(Circle().strokeBorder(tint.opacity(0.25), lineWidth: 1))
    }

    /// Satellites posés en arc sur le côté droit et en haut du disque.
    private func offset(for index: Int, count: Int) -> CGSize {
        let angles: [Double] = [-50, 10, 70, 130]
        let radians = angles[index] * .pi / 180
        let radius = diameter * 0.55
        return CGSize(width: cos(radians) * radius, height: sin(radians) * radius)
    }
}

#Preview("Scènes") {
    VStack(spacing: 32) {
        PickupSymbolScene(main: "qrcode.viewfinder", satellites: ["basket.fill", "house.fill", "clock.fill"])
        PickupSymbolScene(main: "checkmark.seal.fill", satellites: ["basket.fill", "heart.fill"], tint: .economie)
        PickupSymbolScene(main: "calendar.badge.clock", diameter: 72)
    }
    .padding()
    .grenierBackground()
}
