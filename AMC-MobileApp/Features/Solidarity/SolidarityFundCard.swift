import SwiftUI

/// Fonds de solidarité d'un groupe (E10, RQ-080) : solde, paniers offerts ce mois-ci, sans jamais nommer qui est aidé.
///
///     SolidarityFundCard(groupName: "Parc-Ex Ouest", balanceCents: 8_400, basketsThisMonth: 12, basketCostCents: 2_600)
struct SolidarityFundCard: View {
    let groupName: String
    /// Solde disponible du fonds (jamais affiché sous 0).
    let balanceCents: Cents
    /// Paniers suspendus financés ce mois-ci.
    let basketsThisMonth: Int
    /// Coût d'une part type ; s'il est fourni, la carte dit combien de paniers le solde peut encore offrir.
    var basketCostCents: Cents?

    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 52
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(groupName: String, balanceCents: Cents, basketsThisMonth: Int, basketCostCents: Cents? = nil) {
        self.groupName = groupName
        self.balanceCents = balanceCents
        self.basketsThisMonth = basketsThisMonth
        self.basketCostCents = basketCostCents
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: GrenierSymbol.solidarity)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.solidarite)
                    .frame(width: iconSize, height: iconSize)
                    .background(Color.solidarite.opacity(0.12), in: .rect(cornerRadius: 14))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fonds solidaire")
                        .font(.headline)
                        .foregroundStyle(.texte)
                    Text(groupName)
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text(Money.formatRounded(max(0, balanceCents)))
                        .contentTransition(.numericText())
                } icon: {
                    Image(systemName: "banknote.fill")
                        .symbolRenderingMode(.hierarchical)
                        .symbolEffect(.bounce, value: reduceMotion ? 0 : balanceCents)
                }
                .priceStyle()
                .foregroundStyle(Color.solidarite)
                Label {
                    Text(capacityText)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "basket.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.solidarite)
                }
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
            }
            .accessibilityElement(children: .combine)

            Label {
                Text(Self.basketsSentence(count: basketsThisMonth, groupName: groupName))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.texte)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "gift.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.solidarite)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.solidarite.opacity(0.12), in: .rect(cornerRadius: 14))

            Label {
                Text("Personne ne sait qui donne ni qui reçoit.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .symbolRenderingMode(.hierarchical)
            }
            .font(.footnote)
            .foregroundStyle(.texteSecondaire)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
        .accessibilityElement(children: .contain)
    }

    private var capacityText: String {
        guard let basketCostCents else { return "disponibles ce mois-ci" }
        let count = SolidarityMath.basketsCovered(balanceCents: balanceCents, basketCostCents: basketCostCents)
        switch count {
        case 0: return "disponibles, de quoi aider une part de plus bientôt"
        case 1: return "disponibles, de quoi offrir encore 1 panier"
        default: return "disponibles, de quoi offrir encore \(count) paniers"
        }
    }

    /// « 12 paniers suspendus offerts à Parc-Ex Ouest » ; ne nomme jamais un ménage.
    static func basketsSentence(count: Int, groupName: String) -> String {
        switch max(0, count) {
        case 0: "Aucun panier offert ce mois-ci : le premier peut venir de toi."
        case 1: "1 panier suspendu offert à \(groupName) ce mois-ci"
        default: "\(count) paniers suspendus offerts à \(groupName) ce mois-ci"
        }
    }
}

#if DEBUG
#Preview("Clair") {
    ScrollView {
        VStack(spacing: 12) {
            SolidarityFundCard(groupName: "Parc-Ex Ouest", balanceCents: 8_400, basketsThisMonth: 12, basketCostCents: 2_600)
            SolidarityFundCard(groupName: "Villeray Nord", balanceCents: 0, basketsThisMonth: 0)
        }
        .padding()
    }
    .grenierBackground()
}

#Preview("Sombre") {
    ScrollView {
        SolidarityFundCard(groupName: "Parc-Ex Ouest", balanceCents: 8_400, basketsThisMonth: 12, basketCostCents: 2_600)
            .padding()
    }
    .grenierBackground()
    .preferredColorScheme(.dark)
}

#Preview("AX5") {
    ScrollView {
        SolidarityFundCard(groupName: "Parc-Ex Ouest", balanceCents: 8_400, basketsThisMonth: 12, basketCostCents: 2_600)
            .padding()
    }
    .grenierBackground()
    .dynamicTypeSize(.accessibility5)
}
#endif
