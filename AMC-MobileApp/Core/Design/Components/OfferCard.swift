import SwiftUI

/// Un lot dans le fil (maquette F1) : produit, vendeur, échéance, économie, paliers, incitation et prix courant.
struct OfferCard: View {
    let offer: Offer
    let product: Product
    let vendor: Vendor
    /// Parts déjà engagées par le groupe (0 si aucune commande groupée n'est ouverte).
    var committedShares = 0
    var committedHouseholds = 0
    /// Parts déjà réservées par ma famille : une pastille « ✓ 1 part » sur la ligne du prix (0 = pas de pastille).
    var myShareQuantity = 0

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let headerLayout = rowLayout(alignment: .top)
        VStack(alignment: .leading, spacing: 14) {
            // Le badge d'économie a quitté l'en-tête pour la ligne du prix : le titre garde toute la largeur.
            headerLayout {
                ProductIcon(product: product)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(product.name) · \(offer.displayShareUnit)")
                        .font(.headline)
                        .foregroundStyle(.texte)
                    Text("\(Image(systemName: vendor.isVerified ? "checkmark.seal.fill" : "storefront.fill")) \(vendor.legalName) · \(Image(systemName: "clock.fill")) se termine \(deadlineText)")
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                        .symbolRenderingMode(.hierarchical)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                progressBar
                // Sous la barre qu'il explique, sur toute la largeur : une ligne à la taille par défaut,
                // retour à la ligne entre les mots aux grandes tailles, jamais une colonne écrasée.
                statusLabel
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            priceRow
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
        String(localized: "\(FrenchPlural.count(committedHouseholds, "famille")) · \(FrenchPlural.count(committedShares, "part")) sur \(offer.totalShares)")
    }

    /// Lecture VoiceOver courte : « Riz basmati, Ferme Lafleur, 2 dollars 60 le kilo, 37 pour cent moins cher… ».
    var accessibilityText: String {
        var parts = ["\(product.name), \(offer.displayShareUnit)", vendor.legalName, String(localized: "se termine \(deadlineText)"), Money.spoken(currentPriceCents, per: product.unit)]
        if savingsPercent > 0 { parts.append(String(localized: "\(savingsPercent) pour cent moins cher qu'en épicerie")) }
        parts.append(progressText)
        if myShareQuantity > 0 { parts.append(myShareText) }
        if let nudge = progressBar.shortNudge { parts.append(Self.spokenPercent(nudge)) }
        return parts.joined(separator: ", ")
    }

    /// « Ta part : 2 parts », lu par VoiceOver ; la pastille n'affiche que « 2 parts ».
    var myShareText: String {
        String(localized: "Ta part : \(FrenchPlural.count(myShareQuantity, "part"))")
    }

    /// « −19 % » se lit « tiret 19 pour cent » : on écrit le mot.
    static func spokenPercent(_ text: String) -> String {
        text.replacingOccurrences(of: "−", with: "moins ").replacingOccurrences(of: " %", with: String(localized: " pour cent"))
    }

    /// Incitation au prochain palier, ou l'avancement du groupe quand le dernier palier est atteint.
    @ViewBuilder
    private var statusLabel: some View {
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
    }

    /// Prix sur sa propre ligne : montant en avant, unité secondaire qui peut passer à la ligne, badge d'économie à droite.
    /// Si le badge ne tient pas à côté du prix (grandes tailles), il passe dessous.
    private var priceRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                price.fixedSize()
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    shareChip
                    badge
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                price
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        shareChip
                        badge
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        shareChip
                        badge
                    }
                }
            }
        }
    }

    /// Ma part réservée, dans la carte : pilule verte pleine « ✓ 1 part » (distincte du badge d'économie, plus léger).
    @ViewBuilder
    private var shareChip: some View {
        if myShareQuantity > 0 {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text(FrenchPlural.count(myShareQuantity, "part"))
                    .contentTransition(.numericText(value: Double(myShareQuantity)))
            }
            .font(.caption.bold())
            .fontDesign(.rounded)
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(Color.onAccent)
            .background(Color.economie, in: .capsule)
            .fixedSize()
            .accessibilityLabel(myShareText)
        }
    }

    private var price: some View {
        PriceTag(priceCents: currentPriceCents, unit: product.unit, font: .priceCompact)
    }

    @ViewBuilder
    private var badge: some View {
        if savingsPercent > 0 {
            SavingsBadge(kind: .percent(savingsPercent), compact: true)
                .fixedSize()
        }
    }

    private var isAccessibilityLayout: Bool { dynamicTypeSize.isAccessibilitySize }

    /// Ligne horizontale, empilée aux tailles d'accessibilité pour ne rien écraser.
    private func rowLayout(alignment: VerticalAlignment) -> AnyLayout {
        isAccessibilityLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: 12))
    }

    private var deadlineText: String {
        offer.deadline.formatted(.dateTime.weekday(.wide).hour().locale(AppLanguage.formattingLocale))
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
