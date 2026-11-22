import SwiftUI

/// Note moyenne et nombre d'avis, réutilisable partout (cartes de groupe, fiche, vue publique T-172, producteurs).
///
///     RatingSummaryView(summary: group.ratingSummary)                    // « ★ 4,6 · 12 avis »
///     RatingSummaryView(summary: summary, style: .stars)                 // « ★★★★½ 4,6 · 12 avis »
///     RatingSummaryView(summary: summary, showsEmpty: true)              // « Pas encore noté » sans avis
struct RatingSummaryView: View {
    enum Style {
        /// Une étoile, la moyenne et le nombre d'avis : pour les cartes.
        case compact
        /// Cinq étoiles (demi-étoiles comprises), la moyenne et le nombre d'avis : pour les en-têtes.
        case stars
    }

    let summary: RatingRules.Summary
    var style: Style = .compact
    /// Sans avis : « Pas encore noté » (sinon rien n'est affiché).
    var showsEmpty = false
    var font: Font = .subheadline

    var body: some View {
        if let average = summary.average {
            HStack(spacing: 6) {
                switch style {
                case .compact:
                    Image(systemName: "star.fill")
                        .foregroundStyle(.orange)
                        .symbolRenderingMode(.hierarchical)
                        .accessibilityHidden(true)
                case .stars:
                    StarRatingView(rating: average, font: font)
                }
                Text(StarRatingText.average(average))
                    .fontWeight(.semibold)
                    .foregroundStyle(.texte)
                    .contentTransition(.numericText(value: average))
                Text("· \(Self.countText(summary.count))")
                    .foregroundStyle(.texteSecondaire)
                    .contentTransition(.numericText(value: Double(summary.count)))
            }
            .font(font)
            .monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.accessibilityText(summary))
        } else if showsEmpty {
            Label("Pas encore noté", systemImage: "star")
                .font(font)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.texteSecondaire)
        }
    }

    /// « 1 avis », « 12 avis ».
    static func countText(_ count: Int) -> String {
        FrenchPlural.count(count, String(localized: "avis"), plural: String(localized: "avis"))
    }

    /// « Note moyenne 4,6 sur 5, 12 avis ».
    static func accessibilityText(_ summary: RatingRules.Summary) -> String {
        guard let average = summary.average else { return String(localized: "Pas encore noté") }
        return String(localized: "Note moyenne \(StarRatingText.average(average)) sur 5, \(countText(summary.count))")
    }
}

/// Barres de répartition 5 → 1 étoile.
struct RatingDistributionBars: View {
    let summary: RatingRules.Summary

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
                .accessibilityLabel("\(FrenchPlural.count(stars, String(localized: "étoile"))) : \(RatingSummaryView.countText(summary.distribution[stars - 1]))")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Un avis signé « Prénom I. » : pastille d'initiales, étoiles, ligne de contexte et commentaire.
struct RatingCommentCard: View {
    let authorName: String
    let rating: Int
    let comment: String?
    /// « Lot reçu · il y a 3 jours ».
    let caption: String
    var captionSystemImage = "checkmark.seal.fill"
    var isMine = false

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
                        Text(authorName)
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
                    Label(caption, systemImage: captionSystemImage)
                        .font(.caption)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.texteSecondaire)
                }
                Spacer(minLength: 8)
                StarRatingView(rating: Double(rating), font: .caption)
            }
            if let comment {
                Text(comment)
                    .font(.body)
                    .foregroundStyle(.texte)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(authorName), \(FrenchPlural.count(rating, String(localized: "étoile"))). \(comment ?? "")")
    }

    private var initials: String {
        authorName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

#Preview("Notes") {
    let summary = RatingRules.summary(ofRatings: [5, 5, 4, 5, 3, 4])
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            RatingSummaryView(summary: summary)
            RatingSummaryView(summary: summary, style: .stars)
            RatingSummaryView(summary: .empty, showsEmpty: true)
            RatingDistributionBars(summary: summary)
            RatingCommentCard(authorName: "Julie T.", rating: 5,
                              comment: "Coordination au top, on sait toujours où et quand cueillir.",
                              caption: "Membre · il y a 3 jours", captionSystemImage: "person.3.fill", isMine: true)
        }
        .padding()
    }
    .grenierBackground()
}
