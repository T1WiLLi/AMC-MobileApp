import SwiftUI

// Sections de confiance de la page producteur (T-157) : galerie, indicateurs, dernière vente, avis.
// Utilisées par `PublicVendorScreen`.

// MARK: - Galerie

/// Photos de vitrine en bande horizontale ; un tap ouvre la photo en plein écran (balayage entre les photos).
struct VendorGallery: View {
    let photos: [URL]
    let vendorName: String

    @State private var selected: GalleryPick?
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VendorSectionHeader(title: String(localized: "En images"), systemImage: "photo.on.rectangle.angled",
                                count: photos.count)
                .padding(.horizontal)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(photos.enumerated()), id: \.element) { index, url in
                        Button {
                            selected = GalleryPick(url: url)
                        } label: {
                            MediaImage(url: url) {
                                Rectangle().fill(Color.grenier.opacity(0.15))
                                    .overlay { Image(systemName: "photo").foregroundStyle(Color.grenier) }
                            }
                            .frame(width: height * 4 / 3, height: height)
                            .clipShape(.rect(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Photo \(index + 1) sur \(photos.count) de \(vendorName)")
                        .accessibilityHint("Ouvre la photo en grand")
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
        .fullScreenCover(item: $selected) { pick in
            GalleryViewer(photos: photos, start: pick.url)
        }
    }
}

/// Photo choisie dans la galerie (pour `fullScreenCover(item:)`).
private struct GalleryPick: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct GalleryViewer: View {
    let photos: [URL]
    @State var start: URL

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TabView(selection: $start) {
                ForEach(photos, id: \.self) { url in
                    MediaImage(url: url) { ProgressView() }
                        .scaledToFit()
                        .tag(url)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .background(.black)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Coups de cœur

/// Produits mis en avant par le producteur (« Ma vitrine »), avec leur meilleur prix du moment.
struct FeaturedProductsSection: View {
    let products: [Product]
    let bestPrices: [String: Cents]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VendorSectionHeader(title: String(localized: "Ses coups de cœur"), systemImage: "heart.text.square.fill")
            ForEach(products) { product in
                HStack(alignment: .center, spacing: 12) {
                    ProductIcon(product: product)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(product.name)
                            .font(.headline)
                            .foregroundStyle(.texte)
                        Label("\(product.unit) · \(product.origin)", systemImage: "mappin")
                            .font(.caption)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.texteSecondaire)
                    }
                    Spacer(minLength: 8)
                    if let price = bestPrices[product.id] {
                        Text("dès \(Money.format(price))")
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.economie)
                    } else {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(Color.grenier)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .grenierCard()
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Confiance

/// Lots livrés, familles servies, ancienneté, puis la dernière vente.
struct TrustSection: View {
    let trust: VendorReviewRules.Trust

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VendorSectionHeader(title: String(localized: "Pourquoi lui faire confiance"), systemImage: "checkmark.shield.fill")
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                TrustTile(value: "\(trust.deliveredLots)", caption: FrenchPlural.word(trust.deliveredLots, String(localized: "lot livré"), plural: String(localized: "lots livrés")),
                          systemImage: "shippingbox.fill", tint: .grenier)
                TrustTile(value: "\(trust.familiesServed)", caption: FrenchPlural.word(trust.familiesServed, String(localized: "famille servie"), plural: String(localized: "familles servies")),
                          systemImage: "person.3.fill", tint: .economie)
                TrustTile(value: Seniority.value(since: trust.since), caption: String(localized: "sur LeGrenier"),
                          systemImage: "calendar.badge.checkmark", tint: .solidarite)
            }
            LastSaleCard(sale: trust.lastSale)
        }
    }
}

private struct TrustTile: View {
    let value: String
    let caption: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
            Text(value)
                .font(.title.bold())
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.texte)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.texteSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

private struct LastSaleCard: View {
    let sale: VendorSale?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: sale == nil ? "sparkles" : "checkmark.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.economie)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(sale == nil ? "Première vente à venir" : "Dernière vente")
                    .font(.headline)
                    .foregroundStyle(.texte)
                if let sale {
                    Text(SaleText.long(sale))
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                } else {
                    Text("Ce producteur n'a pas encore livré de lot sur LeGrenier. Sois parmi les premières familles !")
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                }
            }
            Spacer(minLength: 0)
        }
        .grenierCard()
        .accessibilityElement(children: .combine)
    }
}

/// Textes d'une vente passée.
nonisolated enum SaleText {
    private static let locale = Locale(identifier: "fr_CA")

    /// « Carottes nantaises · il y a 9 jours ».
    static func short(_ sale: VendorSale) -> String {
        "\(sale.productName) · \(relative(sale.date))"
    }

    /// « Carottes nantaises : 34 parts (sac de 5 kg) pour 21 familles, il y a 9 jours. »
    static func long(_ sale: VendorSale) -> String {
        let shares = FrenchPlural.count(sale.shares, String(localized: "part"))
        let families = FrenchPlural.count(sale.households, String(localized: "famille"))
        return String(localized: "\(sale.productName) : \(shares) (\(sale.shareLabel)) pour \(families), \(relative(sale.date)).")
    }

    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named).locale(locale))
    }
}

/// Ancienneté lisible : « 14 mois », « 2 ans », « 3 sem. ».
nonisolated enum Seniority {
    static func value(since date: Date?, now: Date = .now) -> String {
        guard let date, date < now else { return String(localized: "Nouveau") }
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date, to: now)
        let years = components.year ?? 0, months = components.month ?? 0, days = components.day ?? 0
        if years >= 2 { return String(localized: "\(years) ans") }
        if years == 1 { return months == 0 ? String(localized: "1 an") : String(localized: "\(12 + months) mois") }
        if months >= 1 { return String(localized: "\(months) mois") }
        if days >= 7 { return String(localized: "\(days / 7) sem.") }
        return FrenchPlural.count(max(days, 1), String(localized: "jour"))
    }
}

// MARK: - Avis

/// Note détaillée, bouton pour noter (si le ménage a reçu un lot) et avis récents.
struct ReviewsSection: View {
    let reputation: PublicVendorViewModel.Reputation
    /// Note du catalogue quand il n'y a encore aucun avis.
    var fallbackAverage: Double?
    let rate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VendorSectionHeader(title: String(localized: "Avis des familles"), systemImage: "star.bubble.fill",
                                count: reputation.summary.count)
            RatingSummaryCard(summary: reputation.summary, fallbackAverage: fallbackAverage,
                              reputation: reputation, rate: rate)
            ForEach(reputation.recentReviews) { review in
                ReviewCard(review: review, isMine: review.id == reputation.myReview?.id)
            }
        }
    }
}

private struct RatingSummaryCard: View {
    let summary: VendorReviewRules.Summary
    let fallbackAverage: Double?
    let reputation: PublicVendorViewModel.Reputation
    let rate: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .center, spacing: 20))
            layout {
                VStack(alignment: .leading, spacing: 4) {
                    if let average = summary.average ?? fallbackAverage {
                        Text(StarRatingText.average(average))
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(.texte)
                        StarRatingView(rating: average)
                        Text(summary.count > 0
                             ? FrenchPlural.count(summary.count, String(localized: "avis"), plural: String(localized: "avis"))
                             : String(localized: "note du catalogue"))
                            .font(.caption)
                            .foregroundStyle(.texteSecondaire)
                    } else {
                        Image(systemName: "star.bubble")
                            .font(.largeTitle)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.orange)
                        Text("Aucun avis pour l'instant")
                            .font(.headline)
                            .foregroundStyle(.texte)
                    }
                }
                .accessibilityElement(children: .combine)
                if summary.count > 0 {
                    DistributionBars(summary: summary)
                }
            }

            if reputation.canReview {
                Button(action: rate) {
                    Label(reputation.myReview == nil ? "Noter ce producteur" : "Modifier mon avis",
                          systemImage: reputation.myReview == nil ? "star.leadinghalf.filled" : "pencil")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.glass)
                .tint(.grenier)
                .accessibilityHint(reputation.eligibleSale.map { String(localized: "Ton lot : \(SaleText.short($0))") } ?? "")
            } else {
                Label("Seules les familles qui ont reçu un lot de ce producteur peuvent le noter.",
                      systemImage: "lock.shield.fill")
                    .font(.footnote)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.texteSecondaire)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
    }
}

private struct DistributionBars: View {
    let summary: VendorReviewRules.Summary

    var body: some View {
        VStack(spacing: 4) {
            ForEach((1...5).reversed(), id: \.self) { stars in
                HStack(spacing: 6) {
                    Text("\(stars)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.texteSecondaire)
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.texteSecondaire.opacity(0.15))
                            Capsule().fill(Color.orange)
                                .frame(width: proxy.size.width * summary.share(of: stars))
                        }
                    }
                    .frame(height: 6)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(FrenchPlural.count(stars, String(localized: "étoile"))) : \(FrenchPlural.count(summary.distribution[stars - 1], String(localized: "avis"), plural: String(localized: "avis")))")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ReviewCard: View {
    let review: VendorReview
    let isMine: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(initials)
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.onAccent)
                    .frame(width: 36, height: 36)
                    .background(isMine ? Color.economie : Color.grenier, in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(review.authorName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.texte)
                        if isMine {
                            Text("Ton avis")
                                .font(.caption2.bold())
                                .foregroundStyle(Color.economie)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.economie.opacity(0.15), in: .capsule)
                        }
                    }
                    Label("Lot reçu · \(SaleText.relative(review.updatedAt))", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.texteSecondaire)
                }
                Spacer(minLength: 8)
                StarRatingView(rating: Double(review.rating), font: .caption)
            }
            if let comment = review.comment {
                Text(comment)
                    .font(.body)
                    .foregroundStyle(.texte)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(review.authorName), \(FrenchPlural.count(review.rating, String(localized: "étoile"))). \(review.comment ?? "")")
    }

    private var initials: String {
        review.authorName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}
