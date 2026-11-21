import SwiftUI

/// Prix d'une part ou d'une unité : montant arrondi en gras, unité plus petite, prix en épicerie barré (maquette PriceTag).
struct PriceTag: View {
    let priceCents: Cents
    /// « kg », « caisse »… Affiché « 2,60 $/kg », l'unité en `.subheadline`.
    var unit: String?
    /// Prix de référence en épicerie, barré à côté ; nil pour ne pas l'afficher.
    var referenceCents: Cents?
    var font: Font = .price

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(Money.format(priceCents))
                    .priceStyle(font)
                    .foregroundStyle(.texte)
                    .contentTransition(.numericText(value: Double(priceCents)))
                    .animation(.smooth, value: priceCents)
                if let unit {
                    Text("/\(unit)")
                        .font(.subheadline.weight(.semibold))
                        .fontDesign(.rounded)
                        .foregroundStyle(.texteSecondaire)
                }
            }
            if let referenceCents, referenceCents > priceCents {
                Text(Money.format(referenceCents))
                    .font(.subheadline)
                    .strikethrough()
                    .foregroundStyle(.texteSecondaire)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    var accessibilityText: String {
        var text = "\(Money.format(priceCents))" + (unit.map { " par \($0)" } ?? "")
        if let referenceCents, referenceCents > priceCents {
            text += ", au lieu de \(Money.format(referenceCents)) en épicerie"
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
