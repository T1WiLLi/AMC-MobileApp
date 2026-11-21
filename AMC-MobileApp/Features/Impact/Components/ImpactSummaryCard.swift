import SwiftUI

/// Résumé du mois : « Amina, tu as économisé 48 $ ce mois-ci » ; le quartier 3 900 $ ; 12 paniers suspendus offerts.
/// Carte opaque (Surface) ; l'argent en Economie, les paniers en Solidarite.
struct ImpactSummaryCard: View {
    let snapshot: ImpactSnapshot

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 52

    init(snapshot: ImpactSnapshot) {
        self.snapshot = snapshot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: GrenierSymbol.impact)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.economie)
                    .symbolEffect(.bounce, value: snapshot.currentMonthSavedCents)
                    .frame(width: iconSize, height: iconSize)
                    .background(Color.economie.opacity(0.12), in: .rect(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting)
                        .font(.headline)
                        .foregroundStyle(.texte)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                Label {
                    Text("Tu as économisé")
                } icon: {
                    Image(systemName: "dollarsign.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.economie)
                }
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                AnimatedCounter(value: snapshot.currentMonthSavedCents, format: .money)
                    .priceStyle(.largeTitle.bold())
                    .foregroundStyle(.economie)
                Text("ce mois-ci, par rapport à l'épicerie")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            }

            Divider().overlay(Color.piste)

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            layout {
                stat(
                    value: snapshot.neighborhoodSavedCents, format: .money, tint: .economie,
                    systemImage: GrenierSymbol.savings,
                    caption: "économisés par ton quartier"
                )
                stat(
                    value: snapshot.suspendedBasketsOffered, format: .integer(), tint: .solidarite,
                    systemImage: GrenierSymbol.solidarity,
                    caption: snapshot.suspendedBasketsOffered > 1 ? "paniers suspendus offerts" : "panier suspendu offert"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard(padding: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func stat(value: Int, format: CounterFormat, tint: Color, systemImage: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                AnimatedCounter(value: value, format: format)
                    .priceStyle(.priceCompact)
                    .foregroundStyle(.texte)
            }
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Textes (testés)

    var greeting: String { "Bravo \(snapshot.firstName) !" }

    /// « Novembre à Parc-Extension »
    var subtitle: String {
        let month = snapshot.currentMonthName
        guard let first = month.first else { return snapshot.neighborhoodName }
        return "\(first.uppercased())\(month.dropFirst()) à \(snapshot.neighborhoodName)"
    }

    /// « Amina, tu as économisé 48 $ ce mois-ci. Ton quartier a économisé 3 900 $. 12 paniers suspendus offerts. »
    var accessibilitySummary: String {
        let s = snapshot
        let baskets = ImpactFormat.plural(s.suspendedBasketsOffered, "panier suspendu offert", "paniers suspendus offerts")
        return "\(s.firstName), tu as économisé \(Money.formatRounded(s.currentMonthSavedCents)) ce mois-ci. "
            + "Ton quartier a économisé \(Money.formatRounded(s.neighborhoodSavedCents)). \(baskets)."
    }
}

#Preview("Clair") {
    ScrollView { ImpactSummaryCard(snapshot: .demo).padding() }
        .grenierBackground()
}

#Preview("Sombre") {
    ScrollView { ImpactSummaryCard(snapshot: .demo).padding() }
        .grenierBackground()
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    ScrollView { ImpactSummaryCard(snapshot: .demo).padding() }
        .grenierBackground()
        .dynamicTypeSize(.accessibility5)
}
