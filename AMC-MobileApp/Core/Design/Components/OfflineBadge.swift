import SwiftUI

/// Indicateur discret « Hors ligne » (S-10, T-090) : petite capsule en verre affichée en haut de l'app
/// par `RootView` quand le réseau est coupé. Les données affichées viennent alors du cache.
struct OfflineBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Label("Hors ligne", systemImage: "wifi.slash")
            .font(.footnote.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .symbolEffect(.pulse, options: .repeat(.periodic(delay: 2)), isActive: !reduceMotion)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hors ligne")
            .accessibilityValue("Les données affichées sont les dernières connues.")
            .accessibilityAddTraits(.isStaticText)
    }
}

#Preview("Clair") {
    OfflineBadge()
        .padding()
        .grenierBackground()
}

#Preview("Sombre") {
    OfflineBadge()
        .padding()
        .grenierBackground()
        .preferredColorScheme(.dark)
}
