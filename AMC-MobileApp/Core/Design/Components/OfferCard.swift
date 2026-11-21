import SwiftUI

/// Un lot dans le fil (maquette F1) : produit, vendeur, échéance, économie, paliers, incitation et prix courant.
struct OfferCard: View {
    let offer: Offer
    let product: Product
    let vendor: Vendor
    /// Parts déjà engagées par le groupe (0 si aucune commande groupée n'est ouverte).
    var committedShares = 0
    var committedHouseholds = 0

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let headerLayout = rowLayout(alignment: .top)
        let footerLayout = rowLayout(alignment: .firstTextBaseline)
        VStack(alignment: .leading, spacing: 14) {
            headerLayout {
                ProductIcon(product: product)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(product.name) · \(offer.shareUnit)")
                        .font(.headline)
                        .foregroundStyle(.texte)
                    Text("\(Image(systemName: vendor.isVerified ? "checkmark.seal.fill" : "storefront.fill")) \(vendor.legalName) · \(Image(systemName: "clock.fill")) se termine \(deadlineText)")
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                        .symbolRenderingMode(.hierarchical)
                }
                if !isAccessibilityLayout { Spacer(minLength: 8) }
                if savingsPercent > 0 {
                    SavingsBadge(kind: .percent(savingsPercent), compact: true)
                }
            }

            progressBar

            footerLayout {
                if let nudge = progressBar.shortNudge {
                    Label(nudge, systemImage: "arrow.up.forward.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.grenier)
                        .symbolRenderingMode(.hierarchical)
                        .monospacedDigit()
                } else {
                    Label(progressText, systemImage: "person.2.fill")
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                        .symbolRenderingMode(.hierarchical)
                        .monospacedDigit()
                }
                if !isAccessibilityLayout { Spacer(minLength: 8) }
                PriceTag(priceCents: currentPriceCents, unit: product.unit, font: .priceCompact)
                    // Le prix garde sa largeur ; c'est l'incitation à gauche qui passe à la ligne.
                    .layoutPriority(1)
            }
        }
        .grenierCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Ouvre le lot")
    }

    // MARK: - Calculs (testés)

    var progressBar: TierProgressBar {
        TierProgressBar(
            tiers: offer.tiers,
            committedShares: committedShares,
            totalShares: offer.totalShares,
            compact: true,
            minimumToLaunch: offer.minimumSharesToLaunch
        )
    }

    /// Prix du palier atteint, ou du premier palier si aucun n'est atteint.
    var currentPriceCents: Cents {
        let tiers = offer.sortedTiers
        if let index = offer.tierIndex(forCommittedShares: committedShares) { return tiers[index].priceCents }
        return tiers.first?.priceCents ?? 0
    }

    var savingsPercent: Int {
        Money.savingsPercent(price: currentPriceCents, reference: product.referenceGroceryPriceCents)
    }

    /// « 24 familles · 24 parts sur 40 »
    var progressText: String {
        "\(FrenchPlural.count(committedHouseholds, "famille")) · \(FrenchPlural.count(committedShares, "part")) sur \(offer.totalShares)"
    }

    /// Lecture VoiceOver courte : « Riz basmati, Ferme Lafleur, 2 dollars 60 le kilo, 37 pour cent moins cher… ».
    var accessibilityText: String {
        var parts = ["\(product.name), \(offer.shareUnit)", vendor.legalName, "se termine \(deadlineText)", Money.spoken(currentPriceCents, per: product.unit)]
        if savingsPercent > 0 { parts.append("\(savingsPercent) pour cent moins cher qu'en épicerie") }
        parts.append(progressText)
        if let nudge = progressBar.shortNudge { parts.append(Self.spokenPercent(nudge)) }
        return parts.joined(separator: ", ")
    }

    /// « −19 % » se lit « tiret 19 pour cent » : on écrit le mot.
    static func spokenPercent(_ text: String) -> String {
        text.replacingOccurrences(of: "−", with: "moins ").replacingOccurrences(of: " %", with: " pour cent")
    }

    private var isAccessibilityLayout: Bool { dynamicTypeSize.isAccessibilitySize }

    /// Ligne horizontale, empilée aux tailles d'accessibilité pour ne rien écraser.
    private func rowLayout(alignment: VerticalAlignment) -> AnyLayout {
        isAccessibilityLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: 12))
    }

    private var deadlineText: String {
        offer.deadline.formatted(.dateTime.weekday(.wide).hour().locale(Locale(identifier: "fr_CA")))
    }
}

/// Icône du produit dans un carré teinté (52 pt, suit Dynamic Type).
struct ProductIcon: View {
    let symbol: String

    @ScaledMetric(relativeTo: .title2) private var side: CGFloat = 52

    init(category: Product.Category) {
        symbol = Self.symbol(for: category)
    }

    /// À préférer : le nom du produit affine le symbole (une pomme n'a pas de carotte).
    init(product: Product) {
        symbol = Self.symbol(for: product)
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.title2)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.grenier)
            .frame(width: side, height: side)
            .background(Color.grenier.opacity(0.12), in: .rect(cornerRadius: 14))
            .accessibilityHidden(true)
    }

    /// Symbole d'un produit précis : quelques légumes reconnus par leur nom, sinon celui de la catégorie.
    static func symbol(for product: Product) -> String {
        guard product.category == .produce else { return symbol(for: product.category) }
        let name = product.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_CA"))
        if name.contains("carott") { return "carrot.fill" }
        let leafy = ["laitue", "salade", "epinard", "chou", "kale", "roquette", "basilic"]
        if leafy.contains(where: { name.contains($0) }) { return "leaf.fill" }
        return symbol(for: .produce)
    }

    /// Symbole d'une catégorie. Fruits et légumes : un panier neutre (pommes et pommes de terre n'ont pas de carotte).
    static func symbol(for category: Product.Category) -> String {
        switch category {
        case .produce: "basket.fill"
        case .grains: "shippingbox.fill"
        case .legumes: "leaf.fill"
        case .oils: "drop.fill"
        case .flour: "birthday.cake.fill"
        case .canned: "cylinder.fill"
        case .eggs: "oval.portrait.fill"
        case .meat: "fork.knife"
        case .household: "bubbles.and.sparkles.fill"
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
        radiusMeters: 1_500, coordinatorIds: ["amina"], householdCount: 24, isPublic: true, inviteCode: "PARCEX",
        photoURL: MediaURL.asset("GroupPhotoMarche"), bannerURL: MediaURL.asset("BannerMarche")
    )
}

#Preview("Clair") {
    ScrollView {
        VStack(spacing: 12) {
            OfferCard(offer: CardPreviewData.offer, product: CardPreviewData.product, vendor: CardPreviewData.vendor, committedShares: 25, committedHouseholds: 25)
            OfferCard(offer: CardPreviewData.offer, product: CardPreviewData.product, vendor: CardPreviewData.vendor, committedShares: 3, committedHouseholds: 3)
            OfferCard(offer: CardPreviewData.offer, product: CardPreviewData.product, vendor: CardPreviewData.vendor, committedShares: 30, committedHouseholds: 28)
        }
        .padding()
    }
    .grenierBackground()
}

#Preview("Sombre") {
    OfferCard(offer: CardPreviewData.offer, product: CardPreviewData.product, vendor: CardPreviewData.vendor, committedShares: 25, committedHouseholds: 25)
        .padding()
        .frame(maxHeight: .infinity)
        .grenierBackground()
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    ScrollView {
        OfferCard(offer: CardPreviewData.offer, product: CardPreviewData.product, vendor: CardPreviewData.vendor, committedShares: 25, committedHouseholds: 25)
            .padding()
    }
    .grenierBackground()
    .dynamicTypeSize(.accessibility5)
}

#Preview("AX5 sombre") {
    ScrollView {
        OfferCard(offer: CardPreviewData.offer, product: CardPreviewData.product, vendor: CardPreviewData.vendor, committedShares: 3, committedHouseholds: 3)
            .padding()
    }
    .grenierBackground()
    .dynamicTypeSize(.accessibility5)
    .preferredColorScheme(.dark)
}
#endif
