import SwiftUI

/// Prix d'une part ou d'une unité : montant arrondi en gras + prix en épicerie barré (maquette PriceTag).
struct PriceTag: View {
    let priceCents: Cents
    /// « kg », « caisse »… Affiché « 2,60 $/kg ».
    var unit: String?
    /// Prix de référence en épicerie, barré à côté ; nil pour ne pas l'afficher.
    var referenceCents: Cents?
    var font: Font = .price

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(priceText)
                .priceStyle(font)
                .foregroundStyle(.texte)
                .contentTransition(.numericText(value: Double(priceCents)))
                .animation(.smooth, value: priceCents)
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

    private var priceText: String {
        Money.format(priceCents) + (unit.map { "/\($0)" } ?? "")
    }

    private var accessibilityText: String {
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
    }
    .padding()
}

#Preview("Sombre") {
    PriceTag(priceCents: 260, unit: "kg", referenceCents: 410)
        .padding()
        .preferredColorScheme(.dark)
}
