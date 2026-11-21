import SwiftUI

/// Un lot dans le fil (maquette OfferCard) : produit, vendeur, échéance, économie, paliers, prix courant.
struct OfferCard: View {
    let offer: Offer
    let product: Product
    let vendor: Vendor
    /// Parts déjà engagées par le groupe (0 si aucune commande groupée n'est ouverte).
    var committedShares = 0
    var committedHouseholds = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ProductIcon(category: product.category)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(product.name) · \(offer.shareUnit)")
                        .font(.headline)
                        .foregroundStyle(.texte)
                    Text("\(vendor.legalName) · ferme \(deadlineText)")
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                }
                Spacer(minLength: 8)
                if savingsPercent > 0 {
                    SavingsBadge(kind: .percent(savingsPercent), compact: true)
                }
            }

            TierProgressBar(tiers: offer.tiers, committedShares: committedShares, totalShares: offer.totalShares, compact: true)

            HStack(alignment: .firstTextBaseline) {
                Text(progressText)
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .monospacedDigit()
                Spacer()
                PriceTag(priceCents: currentPriceCents, unit: nil, font: .priceCompact)
            }
        }
        .grenierCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Calculs (testés)

    /// Prix du palier atteint, ou du premier palier si aucun n'est atteint.
    var currentPriceCents: Cents {
        let tiers = offer.sortedTiers
        if let index = offer.tierIndex(forCommittedShares: committedShares) { return tiers[index].priceCents }
        return tiers.first?.priceCents ?? 0
    }

    var savingsPercent: Int {
        Money.savingsPercent(price: currentPriceCents, reference: product.referenceGroceryPriceCents)
    }

    var progressText: String {
        let families = committedHouseholds > 1 ? "familles" : "famille"
        return "\(committedHouseholds) \(families) · \(committedShares) parts sur \(offer.totalShares)"
    }

    private var deadlineText: String {
        offer.deadline.formatted(.dateTime.weekday(.wide).hour().locale(Locale(identifier: "fr_CA")))
    }
}

/// Icône du produit dans un carré teinté de 52 pt.
struct ProductIcon: View {
    let category: Product.Category

    var body: some View {
        Image(systemName: Self.symbol(for: category))
            .font(.title2)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.grenier)
            .frame(width: 52, height: 52)
            .background(Color.grenier.opacity(0.12), in: .rect(cornerRadius: 14))
            .accessibilityHidden(true)
    }

    static func symbol(for category: Product.Category) -> String {
        switch category {
        case .produce: "carrot.fill"
        case .grains: "shippingbox.fill"
        case .dairy: "cup.and.saucer.fill"
        case .meat: "fork.knife"
        case .pantry: "archivebox.fill"
        case .bakery: "basket.fill"
        case .other: "bag.fill"
        }
    }
}

#if DEBUG
enum CardPreviewData {
    static let vendor = Vendor(
        id: "ferme-lafleur", legalName: "Ferme Lafleur", kind: .farm, description: "Céréales et légumineuses de Mirabel",
        photoURLs: [], servedZones: ["parc-ex"], averageRating: 4.8, isVerified: true
    )
    static let product = Product(
        id: "riz-basmati", vendorId: "ferme-lafleur", name: "Riz basmati", category: .grains, unit: "kg",
        origin: "Importé, ensaché à Mirabel", tags: [.vegan], photoURL: nil, referenceGroceryPriceCents: 410
    )
    static let offer = Offer(
        id: "lot-riz", vendorId: "ferme-lafleur", productId: "riz-basmati", totalShares: 40, shareUnit: "sac de 20 kg",
        tiers: [PriceTier(minShares: 1, priceCents: 320), PriceTier(minShares: 11, priceCents: 260), PriceTier(minShares: 26, priceCents: 210)],
        minimumSharesToLaunch: 5, deadline: .now.addingTimeInterval(3 * 86_400), zones: ["parc-ex"], status: .active
    )
    static let group = NeighborhoodGroup(
        id: "parc-ex-ouest", name: "Parc-Ex Ouest", neighborhood: "Parc-Extension", centerGeohash: "f25dv",
        radiusMeters: 1_500, coordinatorIds: ["amina"], householdCount: 24, isPublic: true, inviteCode: "PARCEX"
    )
}

#Preview("Clair") {
    ScrollView {
        OfferCard(offer: CardPreviewData.offer, product: CardPreviewData.product, vendor: CardPreviewData.vendor, committedShares: 24, committedHouseholds: 24)
            .padding()
    }
    .grenierBackground()
}

#Preview("Sombre") {
    OfferCard(offer: CardPreviewData.offer, product: CardPreviewData.product, vendor: CardPreviewData.vendor, committedShares: 24, committedHouseholds: 24)
        .padding()
        .frame(maxHeight: .infinity)
        .grenierBackground()
        .preferredColorScheme(.dark)
}
#endif
