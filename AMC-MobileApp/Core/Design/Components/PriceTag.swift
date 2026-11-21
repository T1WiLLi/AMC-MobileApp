import SwiftUI

/// Prix d'une part ou d'une unité : montant arrondi en gras, unité plus petite, prix en épicerie barré (maquette PriceTag).
struct PriceTag: View {
    let priceCents: Cents
    /// « kg », « caisse »… Affiché « 2,60 $/kg », l'unité en `.subheadline`.
    var unit: String?
    /// Prix de référence en épicerie, barré à côté ; nil pour ne pas l'afficher.
    var referenceCents: Cents?
    var font: Font = .price

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) { priceAndUnit; reference }
            // AX5 : le prix barré passe dessous plutôt que de couper le montant.
            VStack(alignment: .leading, spacing: 2) { priceAndUnit; reference }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var priceAndUnit: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(Money.format(priceCents))
                .priceStyle(font)
                .foregroundStyle(.texte)
                // Le montant ne se coupe jamais (« 11,50 » puis « $ » seul sur la ligne suivante) : seule l'unité passe à la ligne.
                .lineLimit(1)
                .fixedSize()
                .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(priceCents)))
                .grenierAnimation(.smooth, value: priceCents)
            if let unit {
                Text("/\(unit)")
                    .font(.subheadline.weight(.semibold))
                    .fontDesign(.rounded)
                    .foregroundStyle(.texteSecondaire)
            }
        }
    }

    @ViewBuilder
    private var reference: some View {
        if let referenceCents, referenceCents > priceCents {
            // Panier d'épicerie : le prix barré est celui du magasin, pas un ancien prix Grenier.
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Image(systemName: "cart.fill")
                    .imageScale(.small)
                    .symbolRenderingMode(.hierarchical)
                Text(Money.format(referenceCents))
                    .strikethrough()
            }
            .font(.subheadline)
            .foregroundStyle(.texteSecondaire)
        }
    }

    /// « 2 dollars 60 le kilo, au lieu de 4 dollars 10 en épicerie »
    var accessibilityText: String {
        var text = Money.spoken(priceCents, per: unit)
        if let referenceCents, referenceCents > priceCents {
            text += ", au lieu de \(Money.spoken(referenceCents)) en épicerie"
        }
        return text
    }
}

#Preview("Clair") {
    VStack(alignment: .leading, spacing: 16) {
        PriceTag(priceCents: 260, unit: "kg", referenceCents: 410)
        PriceTag(priceCents: 210, unit: "kg", font: .priceCompact)
        PriceTag(priceCents: 1_450)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .grenierBackground()
}

#Preview("Sombre") {
    PriceTag(priceCents: 260, unit: "kg", referenceCents: 410)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    VStack(alignment: .leading, spacing: 16) {
        PriceTag(priceCents: 260, unit: "kg", referenceCents: 410)
        PriceTag(priceCents: 1_450, unit: "caisse", font: .priceCompact)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .grenierBackground()
    .dynamicTypeSize(.accessibility5)
}
