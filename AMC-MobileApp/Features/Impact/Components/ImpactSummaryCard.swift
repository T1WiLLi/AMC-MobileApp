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
                Text(savingsCaption)
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(Color.piste)

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            layout {
                stat(
                    value: snapshot.neighborhoodSavedCents, format: .money, tint: .economie,
                    systemImage: GrenierSymbol.savings,
                    caption: String(localized: "économisés par ton quartier")
                )
                stat(
                    value: snapshot.suspendedBasketsOffered, format: .integer(), tint: .solidarite,
                    systemImage: GrenierSymbol.solidarity,
                    caption: snapshot.suspendedBasketsOffered > 1 ? String(localized: "paniers suspendus offerts") : String(localized: "panier suspendu offert")
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

    /// « Bravo Amina ! » quand le mois rapporte quelque chose ; à 0 $, un encouragement plutôt qu'un bravo.
    var greeting: String {
        let name = snapshot.firstName.trimmingCharacters(in: .whitespaces)
        if snapshot.currentMonthSavedCents > 0 {
            return name.isEmpty ? String(localized: "Bravo !") : String(localized: "Bravo \(name) !")
        }
        return name.isEmpty ? String(localized: "Ta première économie t'attend") : String(localized: "\(name), ta première économie t'attend")
    }

    /// « ce mois-ci, par rapport à l'épicerie », ou la marche à suivre quand rien n'est encore économisé.
    var savingsCaption: String {
        snapshot.currentMonthSavedCents > 0
            ? "ce mois-ci, par rapport à l'épicerie"
            : "ce mois-ci : réserve une part dans un lot pour commencer à économiser"
    }

    /// « Novembre à Parc-Extension » ; sans quartier connu, le mois seul (jamais « Novembre à »).
    var subtitle: String {
        let month = snapshot.currentMonthName
        let neighborhood = snapshot.neighborhoodName.trimmingCharacters(in: .whitespaces)
        guard let first = month.first else { return neighborhood }
        let capitalized = "\(first.uppercased())\(month.dropFirst())"
        return neighborhood.isEmpty ? capitalized : "\(capitalized) à \(neighborhood)"
    }

    /// « Amina, tu as économisé 48 $ ce mois-ci. Ton quartier a économisé 3 900 $. 12 paniers suspendus offerts. »
    var accessibilitySummary: String {
        let s = snapshot
        let baskets = ImpactFormat.plural(s.suspendedBasketsOffered, String(localized: "panier suspendu offert"), String(localized: "paniers suspendus offerts"))
        let saved = Money.formatRounded(s.currentMonthSavedCents)
        let opening = s.firstName.isEmpty
            ? String(localized: "Tu as économisé \(saved) ce mois-ci. ")
            : String(localized: "\(s.firstName), tu as économisé \(saved) ce mois-ci. ")
        return opening
            + String(localized: "Ton quartier a économisé \(Money.formatRounded(s.neighborhoodSavedCents)). \(baskets).")
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
