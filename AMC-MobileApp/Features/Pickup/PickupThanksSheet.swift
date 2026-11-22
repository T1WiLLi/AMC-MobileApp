import SwiftUI

/// Après le scan de l'hôte (retour samuel) : « Bon appétit ! » et, au choix, une note du groupe (T-174) et du
/// producteur (T-157). Mêmes écritures que les fiches : `GroupRatingsViewModel.save` et
/// `PublicVendorViewModel.saveReview` (donc mêmes règles Firestore). Les deux notes sont facultatives :
/// « Envoyer » n'envoie que ce qui est rempli, « Plus tard » ferme sans rien envoyer.
struct PickupThanksSheet: View {
    let groupId: String?
    let groupName: String
    let vendorId: String?
    /// Produit récupéré chez ce producteur (« Pommes de terre jaunes »), pour le contexte de la note.
    let productName: String?

    @Environment(\.appContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var groupRatings: GroupRatingsViewModel?
    @State private var vendor: PublicVendorViewModel?
    @State private var groupStars = 0
    @State private var groupComment = ""
    @State private var vendorStars = 0
    @State private var vendorComment = ""
    @State private var isSaving = false
    @State private var error: AppError?

    private var canRateGroup: Bool { groupRatings?.state.value?.eligibility.canRate == true }
    private var canRateVendor: Bool { vendor?.reputation.value?.canReview == true }
    private var hasRating: Bool { (canRateGroup && groupStars > 0) || (canRateVendor && vendorStars > 0) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    if canRateGroup {
                        PickupStarsCard(title: groupName, systemImage: "person.3.fill",
                                        stars: $groupStars, comment: $groupComment,
                                        maxLength: GroupRating.maxCommentLength)
                    }
                    if canRateVendor {
                        PickupStarsCard(title: vendor?.profile?.name ?? String(localized: "Le producteur"),
                                        subtitle: productName, systemImage: "storefront.fill",
                                        stars: $vendorStars, comment: $vendorComment,
                                        maxLength: VendorReview.maxCommentLength)
                    }
                    if let error {
                        Label(error.message, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.texteSecondaire)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .grenierBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Plus tard") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if canRateGroup || canRateVendor {
                    Button {
                        Task { await submit() }
                    } label: {
                        Group {
                            if isSaving { ProgressView() } else { Text("Envoyer mes notes") }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.grenier)
                    .disabled(!hasRating || isSaving)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
        }
        .presentationDetents([.large])
        .task { await load() }
    }

    private var hero: some View {
        VStack(spacing: 8) {
            Image(systemName: "party.popper.fill")
                .font(.system(.largeTitle))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.economie)
                .accessibilityHidden(true)
            Text("Bon appétit !")
                .font(.title.bold())
                .foregroundStyle(.texte)
            Text("Ta commande est récupérée. Une note ? C'est facultatif.")
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    /// Lit l'éligibilité et les avis existants (préremplis, pour ne jamais effacer un commentaire déjà laissé).
    private func load() async {
        let repositories = context.repositories, householdId = context.householdId, userId = context.userId
        if let groupId, groupRatings == nil {
            let model = GroupRatingsViewModel(repositories: repositories, groupId: groupId,
                                              householdId: householdId, userId: userId)
            groupRatings = model
            let group = try? await repositories.groups.group(id: groupId)
            await model.load(isMember: true, isOwner: group?.creatorId == userId)
            if let mine = model.state.value?.myRating {
                groupStars = mine.rating
                groupComment = mine.comment ?? ""
            }
        }
        if let vendorId, vendor == nil, !householdId.isEmpty {
            let model = PublicVendorViewModel(vendorId: vendorId, repositories: repositories,
                                              viewer: .init(userId: userId, householdId: householdId))
            vendor = model
            await model.load()
            if let mine = model.reputation.value?.myReview {
                vendorStars = mine.rating
                vendorComment = mine.comment ?? ""
            }
        }
    }

    /// N'envoie que les notes remplies ; ferme si tout est passé.
    private func submit() async {
        isSaving = true
        defer { isSaving = false }
        var failure: AppError?
        if canRateGroup, groupStars > 0, let groupRatings,
           case .failure(let groupError) = await groupRatings.save(rating: groupStars, comment: groupComment) {
            failure = groupError
        }
        if canRateVendor, vendorStars > 0, let vendor,
           let vendorError = await vendor.saveReview(rating: vendorStars, comment: vendorComment) {
            failure = vendorError
        }
        if let failure { error = failure } else { dismiss() }
    }
}

/// Carte de note : titre, 1 à 5 étoiles et un commentaire court facultatif.
private struct PickupStarsCard: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    @Binding var stars: Int
    @Binding var comment: String
    let maxLength: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.texte)
                    if let subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.texteSecondaire)
                    }
                }
            } icon: {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
            }
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        stars = stars == value ? 0 : value
                    } label: {
                        Image(systemName: value <= stars ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(value <= stars ? Color.grenier : Color.texteSecondaire)
                            .symbolEffect(.bounce, value: reduceMotion ? false : value <= stars)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Note de \(title)"))
            .accessibilityValue(Text(stars == 0 ? String(localized: "Pas de note") : String(localized: "\(stars) étoiles sur 5")))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: stars = min(5, stars + 1)
                case .decrement: stars = max(0, stars - 1)
                @unknown default: break
                }
            }
            .grenierHaptic(.selection, trigger: stars)
            if stars > 0 {
                TextField("Un commentaire ? (facultatif)", text: $comment, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(12)
                    .background(Color.fond, in: .rect(cornerRadius: 12))
                    .onChange(of: comment) { _, new in
                        if new.count > maxLength { comment = String(new.prefix(maxLength)) }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
        .animation(reduceMotion ? nil : .smooth, value: stars > 0)
    }
}
