import SwiftUI

/// Paliers d'un lot et progression du groupe (maquette TierProgressBar).
///
/// Un segment par palier : il se remplit entre le seuil de son palier et celui du suivant.
/// Le dernier segment se remplit jusqu'à `totalShares` (ou son seuil + 25 % s'il n'est pas fourni).
struct TierProgressBar: View {
    let tiers: [PriceTier]
    let committedShares: Int
    /// Parts totales du lot, pour borner le dernier segment.
    var totalShares: Int?
    /// Unité affichée dans la phrase d'incitation : « famille(s) », « part(s) ».
    var unitSingular = "part"
    var unitPlural = "parts"
    /// Version compacte (hauteur 6, sans légendes) pour OfferCard.
    var compact = false
    /// Parts minimales pour que la commande parte (`Offer.minimumSharesToLaunch`).
    /// nil : le seuil du premier palier fait foi.
    var minimumToLaunch: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var sorted: [PriceTier] { tiers.sorted { $0.minShares < $1.minShares } }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 0 : 8) {
            HStack(spacing: 4) {
                ForEach(Array(sorted.enumerated()), id: \.offset) { index, _ in
                    segment(index: index)
                }
            }
            .frame(height: compact ? 6 : 10)
            .grenierAnimation(.smooth, value: committedShares)

            if !compact {
                legendLayout {
                    ForEach(Array(sorted.enumerated()), id: \.offset) { index, tier in
                        Text(legend(for: index, tier: tier))
                            .font(.caption)
                            .fontWeight(index == currentIndex ? .bold : .regular)
                            .foregroundStyle(index == currentIndex ? Color.texte : Color.texteSecondaire)
                            .frame(maxWidth: .infinity, alignment: legendAlignment(for: index))
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let nudge {
                    Text(nudge)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.grenier)
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Paliers de prix")
        .accessibilityValue(accessibilityText)
    }

    // MARK: - Calculs (internes, testés)

    /// Index du palier atteint, nil si aucun.
    var currentIndex: Int? { sorted.lastIndex { committedShares >= $0.minShares } }

    /// Seuil de lancement : `minimumToLaunch` s'il est fourni, sinon le seuil du premier palier.
    var launchThreshold: Int { minimumToLaunch ?? sorted.first?.minShares ?? 0 }

    /// Remplissage (0…1) du segment `index`.
    func fill(forSegment index: Int) -> Double {
        guard sorted.indices.contains(index) else { return 0 }
        let lower = sorted[index].minShares
        let upper: Int
        if index + 1 < sorted.count {
            upper = sorted[index + 1].minShares
        } else {
            upper = max(totalShares ?? Int((Double(lower) * 1.25).rounded(.up)), lower + 1)
        }
        let span = Double(upper - lower)
        return min(max(Double(committedShares - lower) / span, 0), 1)
    }

    /// « Encore 1 famille pour débloquer −19 % », nil si le dernier palier est atteint.
    var nudge: String? { nudge(short: false) }

    /// Version courte pour le pied d'OfferCard (maquette F1) : « Encore 1 famille pour −19 % ».
    var shortNudge: String? { nudge(short: true) }

    private func nudge(short: Bool) -> String? {
        if committedShares < launchThreshold {
            return "Encore \(count(launchThreshold - committedShares)) pour lancer la commande"
        }
        guard let next = sorted.first(where: { committedShares < $0.minShares }) else { return nil }
        let missing = count(next.minShares - committedShares)
        // Économie du palier suivant par rapport au palier atteint (ou au premier palier).
        let reference = currentIndex.map { sorted[$0].priceCents } ?? sorted.first?.priceCents ?? next.priceCents
        let percent = Money.savingsPercent(price: next.priceCents, reference: reference)
        guard percent > 0 else { return "Encore \(missing) pour le palier suivant" }
        return short ? "Encore \(missing) pour −\(percent) %" : "Encore \(missing) pour débloquer −\(percent) %"
    }

    private func count(_ value: Int) -> String {
        FrenchPlural.count(value, unitSingular, plural: unitPlural)
    }

    var accessibilityText: String {
        var text = "\(count(committedShares)) \(FrenchPlural.word(committedShares, "engagée"))"
        if let currentIndex {
            text += ", prix actuel \(Money.spoken(sorted[currentIndex].priceCents))"
        }
        if let nudge { text += ". \(nudge)" }
        return text
    }

    // MARK: - Vues

    private func segment(index: Int) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.piste)
                Capsule()
                    .fill(Color.grenier)
                    .frame(width: proxy.size.width * fill(forSegment: index))
            }
        }
    }

    /// Légendes en ligne ; empilées aux tailles d'accessibilité pour ne rien tronquer.
    private var legendLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .top))
    }

    private func legend(for index: Int, tier: PriceTier) -> String {
        let range: String
        if index + 1 < sorted.count {
            range = "\(tier.minShares)–\(sorted[index + 1].minShares - 1)"
        } else {
            range = "\(tier.minShares)+"
        }
        return "\(range) · \(Money.format(tier.priceCents))"
    }

    private func legendAlignment(for index: Int) -> Alignment {
        if dynamicTypeSize.isAccessibilitySize || index == 0 { return .leading }
        if index == sorted.count - 1 { return .trailing }
        return .center
    }
}

#Preview("Clair") {
    let tiers = [PriceTier(minShares: 1, priceCents: 320), PriceTier(minShares: 11, priceCents: 260), PriceTier(minShares: 26, priceCents: 210)]
    VStack(spacing: 24) {
        TierProgressBar(tiers: tiers, committedShares: 24, totalShares: 40, unitSingular: "famille", unitPlural: "familles")
            .grenierCard()
        TierProgressBar(tiers: tiers, committedShares: 3, totalShares: 40, minimumToLaunch: 5)
            .grenierCard()
        TierProgressBar(tiers: tiers, committedShares: 24, totalShares: 40, compact: true)
    }
    .padding()
    .frame(maxHeight: .infinity)
    .grenierBackground()
}

#Preview("Sombre") {
    let tiers = [PriceTier(minShares: 1, priceCents: 320), PriceTier(minShares: 11, priceCents: 260), PriceTier(minShares: 26, priceCents: 210)]
    TierProgressBar(tiers: tiers, committedShares: 25, totalShares: 40, unitSingular: "famille", unitPlural: "familles")
        .grenierCard()
        .padding()
        .frame(maxHeight: .infinity)
        .grenierBackground()
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    let tiers = [PriceTier(minShares: 1, priceCents: 320), PriceTier(minShares: 11, priceCents: 260), PriceTier(minShares: 26, priceCents: 210)]
    ScrollView {
        TierProgressBar(tiers: tiers, committedShares: 24, totalShares: 40, unitSingular: "famille", unitPlural: "familles")
            .grenierCard()
            .padding()
    }
    .grenierBackground()
    .dynamicTypeSize(.accessibility5)
}
