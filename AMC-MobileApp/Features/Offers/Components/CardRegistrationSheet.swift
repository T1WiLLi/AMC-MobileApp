import SwiftUI

/// E21-3 « Réserver = enregistrer sa carte » : feuille style Apple Pay montrée avant la première réservation.
/// Paiement simulé : la carte est seulement « enregistrée », rien n'est débité ni retenu avant le prix final.
///
///     .sheet(item: …) { registration in
///         CardRegistrationSheet(registration: registration, shareLabel: "10 kg",
///                               onConfirm: { … }, onCancel: { … })
///     }
struct CardRegistrationSheet: View {
    let registration: OfferDetailViewModel.CardRegistration
    /// Quantité lisible (« 20 kg », « 2 × caisse »).
    let shareLabel: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 24

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PaymentCardView(methodLabel: registration.methodLabel)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tu paieras au plus")
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                    Text(Money.format(registration.maxPriceCents))
                        .priceStyle(.largeTitle.bold())
                        .foregroundStyle(.texte)
                        .contentTransition(.numericText(value: Double(registration.maxPriceCents)))
                    Text(detailText)
                        .font(.footnote)
                        .foregroundStyle(.texteSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 12) {
                    reassurance(String(localized: "Carte enregistrée. Rien n'est débité avant le prix final."),
                                systemImage: "lock.shield.fill")
                    reassurance(String(localized: "Plus le groupe grandit, plus le prix baisse : tu paies le prix du dernier palier atteint."),
                                systemImage: "arrow.down.forward.circle.fill")
                }
                .grenierCard()

                // Aux tailles d'accessibilité, les boutons suivent le contenu au lieu de couvrir la moitié de la feuille.
                if dynamicTypeSize.isAccessibilitySize { buttons }
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Barre de contrôle iOS 26 : le texte qui défile s'arrête net au-dessus des boutons.
        .scrollEdgeEffectStyle(.hard, for: .bottom)
        .safeAreaBar(edge: .bottom, spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize { buttons.padding(.horizontal, 16).padding(.vertical, 8) }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.fraction(0.82), .large])
        .presentationDragIndicator(.visible)
    }

    private var detailText: String {
        if registration.donationCents > 0 {
            return String(localized: "Pour \(shareLabel), dont \(Money.formatRounded(registration.donationCents)) de panier suspendu. Prix final à la clôture de la commande.")
        }
        return String(localized: "Pour \(shareLabel). Prix final à la clôture de la commande.")
    }

    private func reassurance(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .frame(width: iconWidth)
        }
        .font(.subheadline)
        .foregroundStyle(.texte)
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button(action: onConfirm) {
                Label("Confirmer et réserver", systemImage: "cart.fill.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(Color.grenier)

            Button(role: .cancel, action: onCancel) {
                Text("Annuler")
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.glass)
        }
    }
}

#Preview("Carte") {
    Color.fond.sheet(isPresented: .constant(true)) {
        CardRegistrationSheet(
            registration: .init(quantity: 2, maxPriceCents: 2_980, donationCents: 500, methodLabel: PaymentSimulator.methodLabel),
            shareLabel: "20 kg", onConfirm: {}, onCancel: {}
        )
    }
}

#Preview("Carte · sombre") {
    Color.fond.sheet(isPresented: .constant(true)) {
        CardRegistrationSheet(
            registration: .init(quantity: 1, maxPriceCents: 1_150, donationCents: 0, methodLabel: PaymentSimulator.methodLabel),
            shareLabel: "10 kg", onConfirm: {}, onCancel: {}
        )
    }
    .preferredColorScheme(.dark)
}
