import SwiftUI

/// « Avis des familles » d'un groupe (T-174, FB-20) : moyenne, répartition, avis récents et « Noter ce groupe ».
/// Réutilisable dans toute vue d'un groupe (fiche, vue publique T-172) ; sur la fiche publique (T-187), le modèle
/// est en lecture seule (`isReadOnly`) : mêmes avis, sans « Noter ce groupe ». La note compacte des cartes est
/// `RatingSummaryView(summary: group.ratingSummary)`.
///
///     GroupRatingsSection(model: ratings, groupName: group.name) { updated in viewModel.replaceGroup(updated) }
struct GroupRatingsSection: View {
    let model: GroupRatingsViewModel
    let groupName: String
    /// Groupe aux agrégats à jour après un avis (en-tête et cartes).
    var onGroupUpdated: (NeighborhoodGroup) -> Void = { _ in }

    @State private var isRating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupsSectionHeader(title: String(localized: "Avis des familles"), systemImage: "star.bubble.fill",
                                tint: .orange, count: model.state.value?.summary.count)
            switch model.state {
            case .idle, .loading:
                GroupRatingsCard(content: .placeholder, rate: {})
                    .redacted(reason: .placeholder)
                    .accessibilityLabel("Chargement des avis")
            case .failed(let error):
                GroupRatingsError(error: error) { await model.reload() }
            case .empty:
                EmptyView()
            case .loaded(let content):
                GroupRatingsCard(content: content, isReadOnly: model.isReadOnly) { isRating = true }
                ForEach(Array(content.recent.enumerated()), id: \.element.id) { index, rating in
                    RatingCommentCard(
                        authorName: rating.authorName, rating: rating.rating, comment: rating.comment,
                        caption: String(localized: "Famille du groupe · \(SaleText.relative(rating.updatedAt))"),
                        captionSystemImage: "person.3.fill",
                        isMine: rating.id == content.myRating?.id
                    )
                    .grenierAppear(index: index)
                }
            }
        }
        .sheet(isPresented: $isRating) {
            let mine = model.state.value?.myRating
            RatingSheet(
                title: groupName,
                prompt: String(localized: "Comment ça se passe dans ce groupe ?"),
                context: contextLine,
                placeholder: String(localized: "Organisation, ambiance, cueillettes…"),
                maxLength: GroupRating.maxCommentLength,
                existingRating: mine?.rating,
                existingComment: mine?.comment
            ) { rating, comment in
                switch await model.save(rating: rating, comment: comment) {
                case .success(let group):
                    onGroupUpdated(group)
                    return nil
                case .failure(let error):
                    return error
                }
            }
        }
    }

    private var contextLine: RatingSheet.Context? {
        switch model.state.value?.eligibility {
        case .member?: .init(text: String(localized: "Membre du groupe"), systemImage: "person.3.fill")
        case .formerMember?: .init(text: String(localized: "Ancienne famille du groupe"), systemImage: "clock.arrow.circlepath")
        default: nil
        }
    }
}

private extension GroupRatingsViewModel.Content {
    /// Contenu factice du squelette de chargement.
    static let placeholder = Self(summary: RatingRules.summary(ofRatings: [5, 4, 5]), recent: [], myRating: nil,
                                  eligibility: .notEligible)
}

/// Moyenne, étoiles, répartition et action principale de la section.
private struct GroupRatingsCard: View {
    let content: GroupRatingsViewModel.Content
    /// T-187 : fiche publique (visiteur), on lit les avis sans pouvoir noter.
    var isReadOnly = false
    let rate: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.groupTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 20))
            layout {
                VStack(alignment: .leading, spacing: 4) {
                    if let average = content.summary.average {
                        Text(StarRatingText.average(average))
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: average))
                            .foregroundStyle(.texte)
                        StarRatingView(rating: average)
                        Text(RatingSummaryView.countText(content.summary.count))
                            .font(.caption)
                            .foregroundStyle(.texteSecondaire)
                            .contentTransition(.numericText(value: Double(content.summary.count)))
                    } else {
                        Image(systemName: "star.bubble")
                            .font(.largeTitle)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.orange)
                        Text("Aucun avis pour l'instant")
                            .font(.headline)
                            .foregroundStyle(.texte)
                        if content.eligibility.canRate {
                            Text("Sois la première famille à dire comment ça se passe.")
                                .font(.subheadline)
                                .foregroundStyle(.texteSecondaire)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                if content.summary.count > 0 {
                    RatingDistributionBars(summary: content.summary)
                }
            }
            .grenierAnimation(.smooth, value: content.summary)

            if content.eligibility.canRate {
                Button(action: rate) {
                    Label(content.myRating == nil ? "Noter ce groupe" : "Modifier mon avis",
                          systemImage: content.myRating == nil ? "star.leadinghalf.filled" : "pencil")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 4)),
                                      isActive: content.myRating == nil && !reduceMotion)
                }
                .buttonStyle(.glass)
                .tint(theme.accent)
                .accessibilityHint(content.myRating == nil
                                   ? String(localized: "Donne de 1 à 5 étoiles et un commentaire court")
                                   : String(localized: "Change ta note ou ton commentaire"))
            } else if content.eligibility == .owner {
                Label("Tu as créé ce groupe : les avis viennent des autres familles.",
                      systemImage: "person.crop.circle.badge.checkmark")
                    .font(.footnote)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.texteSecondaire)
            } else if isReadOnly {
                Label("Les avis viennent des familles du groupe. Rejoins-le pour donner le tien.",
                      systemImage: "person.3.fill")
                    .font(.footnote)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.texteSecondaire)
            } else {
                Label("Seules les familles membres du groupe, ou qui l'ont été, peuvent le noter.",
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

private struct GroupRatingsError: View {
    let error: AppError
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
            Text(error.message)
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
            Button("Réessayer", systemImage: "arrow.clockwise") { Task { await retry() } }
                .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
    }
}

#Preview("Membre, pas encore noté") {
    @Previewable @State var model = GroupRatingsViewModel(
        repositories: .fake(behavior: .instant), groupId: FakeData.ID.saintMichel,
        householdId: FakeData.ID.aminaHousehold, userId: FakeData.ID.amina
    )
    ScrollView {
        GroupRatingsSection(model: model, groupName: "Voisins de Saint-Michel").padding()
    }
    .grenierBackground()
    .task { await model.load(isMember: true) }
}

#Preview("Déjà noté, sombre") {
    @Previewable @State var model = GroupRatingsViewModel(
        repositories: .fake(behavior: .instant), groupId: FakeData.ID.villerayKitchen,
        householdId: FakeData.ID.aminaHousehold, userId: FakeData.ID.amina
    )
    ScrollView {
        GroupRatingsSection(model: model, groupName: "Cuisine collective Villeray").padding()
    }
    .grenierBackground()
    .preferredColorScheme(.dark)
    .task { await model.load(isMember: true) }
}
