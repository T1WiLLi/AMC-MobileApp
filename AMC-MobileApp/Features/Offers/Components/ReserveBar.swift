import SwiftUI

/// Barre du bas de la fiche lot (F3) : total de la part, économie vs épicerie et bouton « Réserver 10 kg ».
///
/// Couche de contrôle en Liquid Glass : le résumé et le bouton sont deux formes de verre côte à côte
/// (pas de verre sur verre), le bouton est la seule action `.glassProminent` de l'écran, teintée Grenier.
/// À poser par-dessus le contenu avec `.safeAreaInset(edge: .bottom)` (ou `.reserveBar(…)`), sans fond opaque.
struct ReserveBar: View {
    let offer: Offer
    let product: Product
    /// Palier courant du lot (prix d'une part).
    let tier: PriceTier
    /// Nombre de parts choisies.
    let quantity: Int
    /// Réservation en cours : le bouton affiche un indicateur et ne répond plus.
    var isLoading = false
    /// Réservation impossible (lot fermé, déjà réservé…).
    var isDisabled = false
    let onReserve: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .headline) private var buttonHeight: CGFloat = 52

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))

        GlassEffectContainer(spacing: 12) {
            layout {
                summary
                reserveButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .animation(reduceMotion ? nil : .smooth, value: quantity)
        .animation(reduceMotion ? nil : .smooth, value: tier)
        .animation(reduceMotion ? nil : .smooth, value: isLoading)
    }

    // MARK: Sous-vues

    private var summary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Money.format(quote.totalCents))
                .priceStyle(.title2.bold())
                .foregroundStyle(.texte)
                .contentTransition(.numericText(value: Double(quote.totalCents)))
            if quote.savingsCents > 0 {
                Label {
                    Text("−\(Money.format(quote.savingsCents)) vs épicerie")
                        .contentTransition(.numericText(value: Double(quote.savingsCents)))
                } icon: {
                    Image(systemName: "arrow.down.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .symbolEffect(.bounce, value: reduceMotion ? 0 : quote.savingsCents)
                }
                .labelStyle(TightLabelStyle())
                .font(.subheadline.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(.economie)
            } else {
                Label("Payé à la cueillette", systemImage: "creditcard.fill")
                    .labelStyle(TightLabelStyle())
                    .symbolRenderingMode(.hierarchical)
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryAccessibilityText)
    }

    private var reserveButton: some View {
        Button(action: onReserve) {
            ZStack {
                Label {
                    Text("Réserver \(quantityText)")
                        .multilineTextAlignment(.center)
                        .contentTransition(.numericText(value: Double(quantity)))
                } icon: {
                    Image(systemName: "cart.fill.badge.plus")
                        .symbolRenderingMode(.hierarchical)
                        .symbolEffect(.wiggle, value: reduceMotion ? 0 : quantity)
                }
                .font(.headline)
                .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView()
                        .tint(Color.onAccent)
                }
            }
            .foregroundStyle(Color.onAccent)
            .frame(maxWidth: .infinity, minHeight: buttonHeight)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.glassProminent)
        .tint(.grenier)
        .disabled(isDisabled || isLoading || quantity < 1)
        .accessibilityLabel(isLoading ? String(localized: "Réservation en cours") : String(localized: "Réserver \(quantityText) pour \(Money.format(quote.totalCents))"))
        .accessibilityHint("Payé à la cueillette.")
    }

    // MARK: Données dérivées

    private var quote: ShareMath.Quote {
        ShareMath.quote(shares: quantity, tier: tier, product: product)
    }

    private var quantityText: String {
        ShareMath.quantityLabel(shares: quantity, unit: offer.shareUnit)
    }

    private var summaryAccessibilityText: String {
        var text = String(localized: "Total \(Money.format(quote.totalCents)) pour \(quantityText)")
        if quote.savingsCents > 0 {
            text += String(localized: ", \(Money.format(quote.savingsCents)) de moins qu'en épicerie")
        }
        return text
    }
}

extension View {
    /// Pose la `ReserveBar` en bas de l'écran (`safeAreaInset(edge: .bottom)`), par-dessus le contenu qui défile.
    func reserveBar(
        offer: Offer, product: Product, tier: PriceTier, quantity: Int,
        isLoading: Bool = false, isDisabled: Bool = false, onReserve: @escaping () -> Void
    ) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            ReserveBar(offer: offer, product: product, tier: tier, quantity: quantity,
                       isLoading: isLoading, isDisabled: isDisabled, onReserve: onReserve)
        }
    }
}

#if DEBUG
private struct ReserveBarPreview: View {
    @State private var quantity = 10
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            SharePicker(offer: SharePickerPreviewData.offer, product: SharePickerPreviewData.product,
                        tier: SharePickerPreviewData.tier, quantity: $quantity, range: 1...40)
                .padding()
        }
        .grenierBackground()
        .reserveBar(offer: SharePickerPreviewData.offer, product: SharePickerPreviewData.product,
                    tier: SharePickerPreviewData.tier, quantity: quantity, isLoading: isLoading) {
            isLoading = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                isLoading = false
            }
        }
    }
}

#Preview("Clair") { ReserveBarPreview() }

#Preview("Sombre") { ReserveBarPreview().preferredColorScheme(.dark) }

#Preview("AX5") { ReserveBarPreview().dynamicTypeSize(.accessibility5) }

#Preview("Chargement et désactivé") {
    VStack(spacing: 24) {
        ReserveBar(offer: SharePickerPreviewData.offer, product: SharePickerPreviewData.product,
                   tier: SharePickerPreviewData.tier, quantity: 10, isLoading: true) {}
        ReserveBar(offer: SharePickerPreviewData.offer, product: SharePickerPreviewData.product,
                   tier: SharePickerPreviewData.tier, quantity: 10, isDisabled: true) {}
    }
    .frame(maxHeight: .infinity)
    .grenierBackground()
}
#endif
