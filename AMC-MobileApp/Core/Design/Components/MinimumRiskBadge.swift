import SwiftUI

/// Mise en garde « minimum de lancement en danger » (RQ-050, T-104), calculée par `MinimumRisk.assess`.
/// Orange = risque faible (rythme juste), rouge = risque élevé. N'affiche rien au niveau `.none`.
///
///     MinimumRiskBadge(assessment: MinimumRisk.assess(offer: offer, order: order))
struct MinimumRiskBadge: View {
    let assessment: MinimumRisk.Assessment
    /// Version courte pour les cartes : « 6 parts manquantes ».
    var compact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if assessment.level != .none, let message = assessment.message {
            Label {
                Text(compact ? shortLabel : message)
                    .multilineTextAlignment(.leading)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            }
            .font(compact ? .caption.bold() : .subheadline.weight(.semibold))
            .fontDesign(.rounded)
            .monospacedDigit()
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, compact ? 4 : 6)
            .foregroundStyle(Color.texte)
            .background(tint.opacity(0.18), in: .capsule)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(levelLabel) : \(message)")
        }
    }

    private var tint: Color { assessment.level == .high ? .red : .orange }

    private var levelLabel: String {
        assessment.level == .high ? String(localized: "Minimum en danger") : String(localized: "Attention au minimum")
    }

    private var shortLabel: String {
        let missing = assessment.missingShares
        return "\(FrenchPlural.count(missing, "part")) \(FrenchPlural.word(missing, "manquante"))"
    }
}

private enum MinimumRiskPreviewData {
    static let deadline = Date.now.addingTimeInterval(2 * 24 * 3600 + 600)
    static let offer = Offer(
        id: "o1", vendorId: "v1", productId: "p1", totalShares: 40, shareUnit: "10 kg",
        tiers: [PriceTier(minShares: 10, priceCents: 1_150)],
        minimumSharesToLaunch: 10, deadline: deadline, zones: [], status: .active
    )

    static func assessment(committed: Int) -> MinimumRisk.Assessment {
        let order = GroupOrder(id: "go1", groupId: "g1", offerId: "o1", status: .open, currentTierIndex: nil,
                               committedShares: committed, committedHouseholds: committed,
                               pickupPointId: nil, pickupSlots: [])
        return MinimumRisk.assess(offer: offer, order: order)
    }

    static var gallery: some View {
        VStack(alignment: .leading, spacing: 12) {
            MinimumRiskBadge(assessment: assessment(committed: 4))
            MinimumRiskBadge(assessment: assessment(committed: 8))
            HStack {
                MinimumRiskBadge(assessment: assessment(committed: 4), compact: true)
                MinimumRiskBadge(assessment: assessment(committed: 8), compact: true)
            }
            MinimumRiskBadge(assessment: assessment(committed: 10))
        }
        .padding()
    }
}

#Preview("Clair") {
    MinimumRiskPreviewData.gallery
}

#Preview("Sombre") {
    MinimumRiskPreviewData.gallery
        .preferredColorScheme(.dark)
}
