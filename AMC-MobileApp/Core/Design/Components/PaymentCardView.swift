import SwiftUI

/// Carte du portefeuille style Apple Pay (« Apple Pay •••• 4242 »), partagée par la réservation côté Famille
/// (`CardRegistrationSheet`) et le paiement des organismes (T-207). Opaque : c'est du contenu, pas un contrôle.
///
///     PaymentCardView(methodLabel: PaymentSimulator.methodLabel)
///     PaymentCardView(methodLabel: PaymentSimulator.methodLabel, status: .processing)
struct PaymentCardView: View {
    /// Pastille en bas à droite de la carte.
    enum Status: Equatable {
        /// Carte prête (sceau qui rebondit à l'apparition).
        case ready
        /// Paiement en cours : les ondes du sans-contact s'animent.
        case processing
        /// Paiement accepté.
        case approved
        /// Paiement refusé.
        case declined
    }

    let methodLabel: String
    var last4: String = PaymentSimulator.cardLast4
    var status: Status = .ready

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var cardHeight: CGFloat = 120
    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Color.grenier, Color.grenier.opacity(0.72)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(alignment: .leading) {
                HStack {
                    Label(methodLabel, systemImage: "apple.logo")
                        .font(.headline)
                    Spacer(minLength: 8)
                    if !dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: "wave.3.right")
                            .font(.title3)
                            .symbolEffect(.variableColor.iterative,
                                          isActive: !reduceMotion && appeared && status != .declined)
                    }
                }
                Spacer(minLength: 12)
                HStack(alignment: .lastTextBaseline) {
                    Text(verbatim: "•••• \(last4)")
                        .font(.title3.monospacedDigit())
                    Spacer(minLength: 8)
                    Image(systemName: statusSymbol)
                        .font(.title2)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: reduceMotion ? false : appeared)
                        .symbolEffect(.pulse, isActive: !reduceMotion && status == .processing)
                }
            }
            .foregroundStyle(Color.onAccent)
            .padding(16)
        }
        .frame(minHeight: cardHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Carte \(methodLabel)"))
        .accessibilityValue(Text(verbatim: "•••• \(last4)"))
        .onAppear { appeared = true }
    }

    private var statusSymbol: String {
        switch status {
        case .ready, .approved: "checkmark.seal.fill"
        case .processing: "ellipsis.circle.fill"
        case .declined: "xmark.octagon.fill"
        }
    }
}

#Preview("Carte") {
    VStack(spacing: 16) {
        PaymentCardView(methodLabel: PaymentSimulator.methodLabel)
        PaymentCardView(methodLabel: PaymentSimulator.methodLabel, status: .processing)
        PaymentCardView(methodLabel: PaymentSimulator.methodLabel, status: .declined)
    }
    .padding()
    .grenierBackground()
}

#Preview("Carte · sombre") {
    PaymentCardView(methodLabel: PaymentSimulator.methodLabel)
        .padding()
        .grenierBackground()
        .preferredColorScheme(.dark)
}
