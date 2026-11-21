import SwiftUI

/// Choix de la part d'une famille sur un lot (fiche F3, section « Ta part »).
///
/// Picker segmenté sur des pas (5 / 10 / 20 kg par défaut, ou `steps`) + `Stepper` pour une quantité libre
/// dans les bornes. La quantité est un nombre de parts (`Offer.shareUnit`). L'économie vs épicerie s'anime
/// (`numericText`) et chaque changement donne un retour haptique de sélection. Aucune logique métier :
/// le calcul est dans `ShareMath`.
struct SharePicker: View {
    let offer: Offer
    let product: Product
    /// Palier courant du lot (prix d'une part).
    let tier: PriceTier
    /// Nombre de parts choisies.
    @Binding var quantity: Int
    /// Pas du Picker segmenté, en parts ; nil = `ShareMath.defaultSteps`.
    var steps: [Int]?
    /// Bornes de la part ; nil = de 1 aux parts du lot.
    var range: ClosedRange<Int>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ta part")
                .font(.title3.bold())
                .foregroundStyle(.texte)
                .accessibilityAddTraits(.isHeader)

            if resolvedSteps.count > 1 {
                Picker("Ta part", selection: stepSelection) {
                    ForEach(resolvedSteps, id: \.self) { step in
                        Text(label(for: step)).tag(Optional(step))
                    }
                }
                .pickerStyle(.segmented)
            }

            Stepper(value: clampedQuantity, in: bounds) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Quantité")
                        .foregroundStyle(.texteSecondaire)
                    Spacer(minLength: 8)
                    Text(label(for: quantity))
                        .font(.body.weight(.semibold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(.texte)
                        .contentTransition(.numericText(value: Double(quantity)))
                }
            }
            .accessibilityLabel("Quantité")
            .accessibilityValue(label(for: quantity))

            savingsLine
        }
        .animation(reduceMotion ? nil : .smooth, value: quantity)
        .sensoryFeedback(.selection, trigger: quantity)
        .onAppear {
            let clamped = ShareMath.clamp(quantity, to: bounds)
            if clamped != quantity { quantity = clamped }
        }
    }

    // MARK: Sous-vues

    @ViewBuilder
    private var savingsLine: some View {
        let quote = ShareMath.quote(shares: quantity, tier: tier, product: product)
        Group {
            if quote.savingsCents > 0 {
                Text("Tu économises \(Text(Money.formatRounded(quote.savingsCents)).bold().foregroundStyle(.economie)) sur ta part.")
                    .contentTransition(.numericText(value: Double(quote.savingsCents)))
            } else {
                Text("Le prix baisse quand d'autres familles se joignent au lot.")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.texteSecondaire)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Données dérivées

    private var bounds: ClosedRange<Int> {
        range ?? ShareMath.bounds(for: offer)
    }

    private var resolvedSteps: [Int] {
        let base = steps?.filter(bounds.contains) ?? ShareMath.defaultSteps(for: offer.shareUnit, in: bounds)
        return Array(Set(base)).sorted()
    }

    /// Le segment correspondant à la quantité, ou aucun si elle a été choisie au Stepper.
    private var stepSelection: Binding<Int?> {
        Binding(
            get: { resolvedSteps.contains(quantity) ? quantity : nil },
            set: { if let value = $0 { quantity = ShareMath.clamp(value, to: bounds) } }
        )
    }

    private var clampedQuantity: Binding<Int> {
        Binding(
            get: { ShareMath.clamp(quantity, to: bounds) },
            set: { quantity = ShareMath.clamp($0, to: bounds) }
        )
    }

    private func label(for shares: Int) -> String {
        ShareMath.quantityLabel(shares: shares, unit: offer.shareUnit)
    }
}

#if DEBUG
/// Lot de démo de la maquette F3 (riz basmati vendu au kilo), pour les previews de la fiche lot.
enum SharePickerPreviewData {
    static let product = Product(
        id: "preview-riz", vendorId: "preview-lafleur", name: "Riz basmati", category: .grains, unit: "kg",
        origin: "Mirabel, QC", tags: [.local], photoURL: nil, referenceGroceryPriceCents: 410
    )
    static let offer = Offer(
        id: "preview-offre-riz", vendorId: "preview-lafleur", productId: "preview-riz", totalShares: 200,
        shareUnit: "kg",
        tiers: [PriceTier(minShares: 1, priceCents: 320), PriceTier(minShares: 11, priceCents: 260),
                PriceTier(minShares: 26, priceCents: 210)],
        minimumSharesToLaunch: 50, deadline: .now.addingTimeInterval(3 * 86_400), zones: ["h3n"], status: .active
    )
    static let tier = PriceTier(minShares: 11, priceCents: 260)
}

private struct SharePickerPreview: View {
    @State private var quantity = 10

    var body: some View {
        SharePicker(offer: SharePickerPreviewData.offer, product: SharePickerPreviewData.product,
                    tier: SharePickerPreviewData.tier, quantity: $quantity, range: 1...40)
            .padding()
            .frame(maxHeight: .infinity, alignment: .top)
            .grenierBackground()
    }
}

#Preview("Clair") { SharePickerPreview() }

#Preview("Sombre") { SharePickerPreview().preferredColorScheme(.dark) }

#Preview("AX5") { SharePickerPreview().dynamicTypeSize(.accessibility5) }
#endif
