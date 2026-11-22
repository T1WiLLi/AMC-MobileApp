import MapKit
import SwiftUI

/// F2 Fiche d'un groupe de quartier (maquette `docs/maquettes/F2-groupe.png`) :
/// carte du quartier, nom, membres, point et horaire de cueillette, lots ouverts, invitation, Rejoindre.
/// Poussée dans le NavigationStack de l'onglet Groupes (qui enregistre `.offerDestination()`).
struct GroupDetailScreen: View {
    let groupId: String

    @Environment(\.appContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: GroupDetailViewModel?
    /// T-122 : photo et bannière du groupe (proposées au coordinateur seulement).
    @State private var imageEditor: GroupImageEditorViewModel?
    /// B-036 : feuille « Marque du groupe » (coordinateur seulement).
    @State private var brandingEditor: GroupBrandingEditorViewModel?

    /// Thème du groupe chargé (Grenier tant qu'il charge).
    private var theme: GroupTheme {
        viewModel?.state.value.map { GroupTheme(group: $0.group) } ?? .grenier
    }

    var body: some View {
        Group {
            if let viewModel {
                switch viewModel.state {
                case .idle, .loading:
                    GroupsLoadingScene(title: "Chargement du groupe…", systemImage: GrenierSymbol.map)
                case .empty:
                    GroupsIllustratedState(
                        scene: GroupsSymbolScene(
                            systemImage: "questionmark.folder.fill",
                            satellites: [
                                .init(systemImage: GrenierSymbol.groups, tint: .texteSecondaire, degrees: -150),
                                .init(systemImage: "mappin.slash", tint: .grenier, degrees: -30)
                            ]
                        ),
                        title: "Groupe introuvable",
                        message: "Ce groupe n'existe plus. Il a peut-être été fermé par son coordinateur."
                    )
                case .failed(let error):
                    GroupsErrorState(error: error, retry: { await viewModel.load() })
                case .loaded(let content):
                    // T-172 (FB-13) : un visiteur voit la fiche publique ; un membre (ou un coordonnateur) la fiche complète.
                    if content.audience.isMember || viewModel.isCoordinator {
                        GroupDetailContent(content: content, viewModel: viewModel,
                                           imageEditor: viewModel.isCoordinator ? imageEditor : nil)
                            .transition(.opacity)
                    } else {
                        GroupPublicContent(content: content, viewModel: viewModel)
                            .transition(.opacity)
                    }
                }
            } else {
                GroupsLoadingScene(title: "Chargement du groupe…", systemImage: GrenierSymbol.map)
            }
        }
        .grenierBackground()
        // B-034 : accent et emblème de la marque du groupe ; Grenier revient en quittant la fiche.
        .environment(\.groupTheme, theme)
        .tint(theme.accent)
        .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: theme)
        // Rejoindre : la fiche publique laisse place à la fiche complète en fondu.
        .animation(reduceMotion ? nil : .smooth, value: viewModel?.state.value?.isMember)
        .navigationTitle(theme.displayName ?? String(localized: "Groupe"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let group = viewModel?.state.value?.group, viewModel?.isCoordinator == true {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Marque du groupe", systemImage: "paintpalette") {
                        brandingEditor = GroupBrandingEditorViewModel(
                            repositories: context.repositories, group: group, userId: context.userId
                        )
                    }
                }
            }
            // B-056 : un groupe privé ne se partage pas par son code fixe (invitations à usage unique).
            if let group = viewModel?.state.value?.group, group.isPublic {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: GroupInvite.message(for: group)) {
                        Label("Partager le groupe", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .refreshable { await viewModel?.load() }
        .sheet(item: $brandingEditor) { editor in
            GroupBrandingEditorScreen(viewModel: editor) { updated in
                viewModel?.replaceGroup(updated)
            }
        }
        .alert(
            viewModel?.actionError?.title ?? "",
            isPresented: Binding(
                get: { viewModel?.actionError != nil },
                set: { if !$0 { viewModel?.actionError = nil } }
            ),
            presenting: viewModel?.actionError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
        // Retrait d'une image refusé (hors de la feuille d'aperçu).
        .alert(
            "Image non modifiée",
            isPresented: Binding(
                get: { imageEditor?.error != nil && imageEditor?.isPresentingPreview == false },
                set: { if !$0 { imageEditor?.clearError() } }
            ),
            presenting: imageEditor?.error
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
        .task(id: groupId) {
            guard viewModel == nil else { return }
            let model = GroupDetailViewModel(
                repositories: context.repositories,
                householdId: context.householdId,
                groupId: groupId,
                userId: context.userId
            )
            viewModel = model
            imageEditor = GroupImageEditorViewModel(repositories: context.repositories, groupId: groupId, userId: context.userId)
            await model.load()
        }
    }
}

// MARK: - Contenu

private struct GroupDetailContent: View {
    @Environment(\.groupTheme) private var theme
    let content: GroupDetailViewModel.Content
    let viewModel: GroupDetailViewModel
    /// T-122 : présent seulement pour un coordinateur.
    let imageEditor: GroupImageEditorViewModel?

    @State private var isConfirmingLeave = false
    /// T-174 : avis des familles sur le groupe.
    @State private var ratings: GroupRatingsViewModel?
    /// B-056 : visibilité et invitations, pour le créateur du groupe seulement.
    @State private var invitations: GroupInvitationsViewModel?
    /// B-056 : feuille « Rejoindre avec un code » (groupe privé).
    @State private var isJoiningWithCode = false
    @Environment(\.appContext) private var context
    /// Rejoindre ou quitter change le groupe actif : l'Accueil suit (contexte rechargé).
    @Environment(SessionContextStore.self) private var contextStore: SessionContextStore?
    /// Le nom passe dans la barre de navigation une fois la bannière remontée.
    @State private var showsNavigationTitle = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var group: NeighborhoodGroup { content.group }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupHeroHeader(group: group, editor: imageEditor) { updated in
                    viewModel.replaceGroup(updated)
                }

                VStack(alignment: .leading, spacing: 24) {
                    header

                    if content.isMember {
                        MemberBanner(isMember: content.isMember)
                            .grenierTransition(.banner)
                    }

                    keyFigures

                    VStack(alignment: .leading, spacing: 12) {
                        GroupsSectionHeader(title: "Le quartier", systemImage: GrenierSymbol.map, tint: .grenier)
                        GroupMapHeader(group: group, hasPickupPoint: content.pickupPoint != nil)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        GroupsSectionHeader(title: "Cueillette", systemImage: "figure.walk", tint: .economie)
                        PickupCard(pickupPoint: content.pickupPoint, slot: content.nextSlot)
                    }

                    openOrdersSection

                    // T-174 (FB-20) : avis des familles, « Noter ce groupe » pour les membres et anciens membres.
                    if let ratings {
                        GroupRatingsSection(model: ratings, groupName: theme.displayName ?? group.name) { updated in
                            viewModel.replaceGroup(updated)
                        }
                    }

                    // S-07 (T-108) : envies des familles, réservées aux membres.
                    if content.isMember {
                        NavigationLink {
                            GroupWishesScreen(groupId: group.id)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Ce que le groupe veut")
                                        .font(.headline)
                                        .foregroundStyle(.texte)
                                    Text("Dis ce que ta famille veut acheter, vois la demande du quartier.")
                                        .font(.subheadline)
                                        .foregroundStyle(.texteSecondaire)
                                        .multilineTextAlignment(.leading)
                                }
                            } icon: {
                                Image(systemName: "basket.fill")
                                    .font(.title2)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(theme.accent)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .trailing) {
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.texteSecondaire)
                                    .accessibilityHidden(true)
                            }
                            .grenierCard()
                        }
                        .buttonStyle(.plain)
                    }

                    // B-056 : le créateur choisit public ou privé et gère les invitations à usage unique.
                    if let invitations {
                        GroupPrivacyCard(model: invitations) { viewModel.replaceGroup($0) }
                    }
                    if group.isPublic {
                        InvitationCard(group: group)
                    } else if invitations == nil {
                        PrivateGroupNote(isMember: content.isMember)
                    }

                    if content.isMember {
                        Button(role: .destructive) {
                            isConfirmingLeave = true
                        } label: {
                            Label("Quitter le groupe", systemImage: "rectangle.portrait.and.arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .disabled(viewModel.isUpdatingMembership)
                        .confirmationDialog("Quitter \(group.name) ?", isPresented: $isConfirmingLeave, titleVisibility: .visible) {
                            Button("Quitter le groupe", role: .destructive) {
                                Task {
                                    await viewModel.leave()
                                    await contextStore?.reload()
                                }
                            }
                            Button("Annuler", role: .cancel) {}
                        } message: {
                            Text("Tes parts déjà réservées restent valides. Tu pourras revenir quand tu veux.")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        // La bannière passe sous la barre de navigation (et s'étire en tirant vers le bas).
        .ignoresSafeArea(.container, edges: .top)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y > GroupHeroHeader.bannerHeight - 80
        } action: { _, isPastBanner in
            withAnimation(reduceMotion ? nil : .grenierSmooth) { showsNavigationTitle = isPastBanner }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(group.name)
                    .font(.headline)
                    .lineLimit(1)
                    .opacity(showsNavigationTitle ? 1 : 0)
                    .accessibilityHidden(!showsNavigationTitle)
            }
        }
        .task(id: [content.isMember, viewModel.isCreator]) {
            let model = ratings ?? GroupRatingsViewModel(repositories: context.repositories, groupId: group.id,
                                                         householdId: context.householdId, userId: context.userId)
            ratings = model
            await model.load(isMember: content.isMember, isOwner: viewModel.isCreator)
        }
        .task(id: viewModel.isCreator) {
            guard viewModel.isCreator, invitations == nil else { return }
            let userId = context.userId
            let model = GroupInvitationsViewModel(repositories: context.repositories, group: group, userId: userId)
            invitations = model
            await model.load()
        }
        .sheet(isPresented: $isJoiningWithCode) {
            JoinWithCodeSheet(repositories: context.repositories, householdId: context.householdId) { joined in
                Task {
                    await viewModel.load()
                    await contextStore?.reload(preferring: joined.id)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !content.isMember {
                Button {
                    // B-056 : un groupe privé s'ouvre seulement avec une invitation.
                    if group.isPublic {
                        Task {
                            await viewModel.join()
                            await contextStore?.reload(preferring: group.id)
                        }
                    } else {
                        isJoiningWithCode = true
                    }
                } label: {
                    Group {
                        if viewModel.isUpdatingMembership {
                            ProgressView()
                        } else {
                            Label(group.isPublic ? "Rejoindre le groupe" : "Rejoindre avec une invitation",
                                  systemImage: group.isPublic ? "person.badge.plus" : "ticket.fill")
                                .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 3)), isActive: !reduceMotion)
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(theme.accent)
                .controlSize(.large)
                .disabled(viewModel.isUpdatingMembership)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: content.isMember)
        .sensoryFeedback(.success, trigger: content.isMember)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "Groupe de quartier · \(group.neighborhood)").uppercased(), systemImage: "mappin.circle.fill")
                .font(.caption.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.accent)
            Label {
                Text(theme.displayName ?? group.name)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.texte)
            } icon: {
                Image(systemName: theme.emblem)
                    .font(.title.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.accent)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .accessibilityAddTraits(.isHeader)
            // T-174 : note moyenne des familles (agrégats du groupe).
            RatingSummaryView(summary: group.ratingSummary, style: .stars)
                .grenierAnimation(.smooth, value: group.ratingSummary)
            if let welcome = theme.welcomeMessage {
                Text(welcome)
                    .font(.body)
                    .foregroundStyle(.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { members }
                VStack(alignment: .leading, spacing: 8) { members }
            }
        }
    }

    @ViewBuilder
    private var members: some View {
        let initials = content.memberInitials
        AvatarStack(initials: initials, extraCount: max(group.householdCount - initials.count, 0))
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(FrenchPlural.count(group.householdCount, "famille"))
                    .contentTransition(.numericText(value: Double(group.householdCount)))
            } icon: {
                Image(systemName: "person.2.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.solidarite)
            }
            .font(.body)
            .foregroundStyle(.texteSecondaire)
        }
    }

    /// Chiffres clés du groupe : familles, lots ouverts, rayon du quartier.
    private var keyFigures: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { keyFigureTiles }
            VStack(spacing: 8) { keyFigureTiles }
        }
    }

    @ViewBuilder
    private var keyFigureTiles: some View {
        let orders = content.openOrders.count
        GroupsStatTile(value: "\(group.householdCount)", caption: FrenchPlural.word(group.householdCount, "famille", plural: "familles"),
                       systemImage: "person.2.fill", tint: .solidarite)
        GroupsStatTile(value: "\(orders)", caption: FrenchPlural.word(orders, "lot ouvert", plural: "lots ouverts"),
                       systemImage: GrenierSymbol.offers, tint: theme.accent)
        GroupsStatTile(value: GroupCard.distanceText(group.radiusMeters), caption: "de rayon",
                       systemImage: "circle.dashed", tint: .economie)
    }

    /// « Lot ouvert » / « Lots ouverts » (« Open bundle(s) » en anglais), première lettre en capitale.
    private static func openOrdersTitle(_ count: Int) -> String {
        let word = FrenchPlural.word(count, "lot ouvert", plural: "lots ouverts")
        return word.prefix(1).uppercased() + word.dropFirst()
    }

    @ViewBuilder
    private var openOrdersSection: some View {
        let orders = content.openOrders
        VStack(alignment: .leading, spacing: 12) {
            GroupsSectionHeader(
                title: Self.openOrdersTitle(orders.count),
                systemImage: GrenierSymbol.offers,
                tint: theme.accent,
                count: orders.count
            )
            if orders.isEmpty {
                VStack(spacing: 8) {
                    GroupsSymbolScene(
                        systemImage: "shippingbox",
                        satellites: [
                            .init(systemImage: "clock.fill", tint: theme.accent, degrees: -35),
                            .init(systemImage: GrenierSymbol.impact, tint: .economie, degrees: 145)
                        ],
                        diameter: 64,
                        badgeBackground: .fond
                    )
                    Text("Aucun lot ouvert")
                        .font(.headline)
                        .foregroundStyle(.texte)
                    Text("Le groupe n'a pas de commande en cours. Les nouveaux lots du quartier apparaîtront ici.")
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .grenierCard()
                .accessibilityElement(children: .combine)
            } else {
                ForEach(orders) { summary in
                    NavigationLink(value: OfferRoute(offerId: summary.offer.id)) {
                        OfferCard(
                            offer: summary.offer,
                            product: summary.product,
                            vendor: summary.vendor,
                            committedShares: summary.committedShares,
                            committedHouseholds: summary.committedHouseholds
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Ouvre la fiche du lot.")
                }
            }
        }
    }
}

// MARK: - Bandeau membre

/// Succès : le ménage fait partie du groupe (le sceau rebondit à l'arrivée, sauf sous Reduce Motion).
private struct MemberBanner: View {
    let isMember: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.economie)
                .groupsBounce(value: isMember)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tu en fais partie")
                    .font(.headline)
                    .foregroundStyle(.texte)
                Label("Tu vois ses lots et l'horaire de cueillette en premier.", systemImage: "bell.badge.fill")
                    .font(.subheadline)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.texteSecondaire)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.economie.opacity(0.12), in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Carte du quartier

/// Carte MapKit centrée sur la zone du groupe (cercle) et le point de cueillette.
private struct GroupMapHeader: View {
    @Environment(\.groupTheme) private var theme
    let group: NeighborhoodGroup
    let hasPickupPoint: Bool

    @ScaledMetric(relativeTo: .title) private var height: CGFloat = 240

    var body: some View {
        let center = GroupGeohash.center(of: group.centerGeohash)
        let span = Double(group.radiusMeters) * 3
        Map(initialPosition: .region(MKCoordinateRegion(center: center, latitudinalMeters: span, longitudinalMeters: span)),
            interactionModes: []) {
            MapCircle(center: center, radius: CLLocationDistance(group.radiusMeters))
                .foregroundStyle(theme.accent.opacity(0.12))
                .stroke(theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            if hasPickupPoint {
                Annotation("Point de cueillette", coordinate: center) {
                    Image(systemName: GrenierSymbol.offers)
                        .font(.headline)
                        .foregroundStyle(Color.onAccent)
                        .padding(10)
                        .background(theme.accent, in: .rect(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.surface, lineWidth: 3))
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: min(height, 360))
        .overlay(alignment: .bottomLeading) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    mapBadge(group.neighborhood, systemImage: "mappin.circle.fill")
                    mapBadge("Rayon \(GroupCard.distanceText(group.radiusMeters))", systemImage: "circle.dashed")
                }
            }
            .padding(12)
        }
        .clipShape(.rect(cornerRadius: 24))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Carte du quartier \(group.neighborhood), rayon de \(GroupCard.distanceText(group.radiusMeters))")
    }

    private func mapBadge(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Cueillette

private struct PickupCard: View {
    @Environment(\.groupTheme) private var theme
    let pickupPoint: PickupPoint?
    let slot: PickupSlot?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            row(symbol: pickupPoint == nil ? "mappin.slash" : "mappin.and.ellipse", tint: .economie,
                title: pickupPoint?.name ?? String(localized: "Point de cueillette à venir"),
                subtitle: pickupPoint.map { String(localized: "Point de cueillette · \($0.address)") }
                    ?? String(localized: "L'hôte sera choisi à la prochaine commande"))
            Divider().overlay(Color.piste)
            row(symbol: slot == nil ? "clock.badge.questionmark" : "clock.fill", tint: theme.accent,
                title: slot.map(PickupTime.text(for:)) ?? String(localized: "Horaire à venir"),
                subtitle: slot == nil ? String(localized: "Annoncé dès qu'une commande est lancée") : String(localized: "Prochaine cueillette"))
        }
        .grenierCard()
    }

    private func row(symbol: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.texte)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Invitation

private struct InvitationCard: View {
    @Environment(\.groupTheme) private var theme
    let group: NeighborhoodGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Invite tes voisins", systemImage: "person.badge.plus")
                .font(.headline)
                .foregroundStyle(.texte)
                .symbolRenderingMode(.hierarchical)
            Text("Plus vous êtes nombreux, plus le prix baisse. Partage le code du groupe :")
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
            ViewThatFits(in: .horizontal) {
                HStack { code; Spacer(minLength: 8); share }
                VStack(alignment: .leading, spacing: 12) { code; share }
            }
        }
        .grenierCard()
    }

    private var code: some View {
        Label(group.inviteCode, systemImage: "ticket.fill")
            .font(.title3.bold())
            .fontDesign(.monospaced)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.accent.opacity(0.12), in: .capsule)
            .textSelection(.enabled)
            .accessibilityLabel("Code d'invitation \(group.inviteCode.map(String.init).joined(separator: " "))")
    }

    private var share: some View {
        ShareLink(item: GroupInvite.message(for: group)) {
            Label("Inviter", systemImage: "square.and.arrow.up")
                .fontWeight(.semibold)
        }
        .buttonStyle(.glass)
        .tint(theme.accent)
    }
}

// MARK: - Aides de présentation

private enum GroupInvite {
    static func message(for group: NeighborhoodGroup) -> String {
        String(localized: "Rejoins « \(group.name) » sur LeGrenier pour acheter en gros avec tes voisins de \(group.neighborhood). Code : \(group.inviteCode)")
    }
}

enum PickupTime {
    private static var locale: Locale { AppLanguage.formattingLocale }

    /// « Jeudi, 17 h – 18 h 30 »
    static func text(for slot: PickupSlot) -> String {
        let day = slot.start.formatted(.dateTime.weekday(.wide).locale(locale))
        return "\(day.prefix(1).uppercased())\(day.dropFirst()), \(hour(slot.start)) – \(hour(slot.end))"
    }

    /// « 17 h » ou « 18 h 30 », arrondi au quart d'heure le plus proche (un créneau ne s'annonce pas « 14 h 33 »).
    static func hour(_ date: Date) -> String {
        let quarter: TimeInterval = 15 * 60
        let rounded = Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / quarter).rounded() * quarter)
        let parts = Calendar.current.dateComponents([.hour, .minute], from: rounded)
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0
        if locale.language.languageCode?.identifier == "en" {
            return rounded.formatted(.dateTime.hour().minute().locale(locale))
        }
        return minute == 0 ? "\(hour) h" : String(format: "%d h %02d", hour, minute)
    }
}

/// Décodage d'un geohash vers le centre de sa cellule (pour placer la carte du groupe).
enum GroupGeohash {
    private static let alphabet = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    static func center(of hash: String) -> CLLocationCoordinate2D {
        var latitude = (-90.0, 90.0), longitude = (-180.0, 180.0)
        var isLongitude = true
        for character in hash.lowercased() {
            guard let value = alphabet.firstIndex(of: character) else { break }
            for bit in (0..<5).reversed() {
                let isSet = (value >> bit) & 1 == 1
                if isLongitude {
                    let mid = (longitude.0 + longitude.1) / 2
                    if isSet { longitude.0 = mid } else { longitude.1 = mid }
                } else {
                    let mid = (latitude.0 + latitude.1) / 2
                    if isSet { latitude.0 = mid } else { latitude.1 = mid }
                }
                isLongitude.toggle()
            }
        }
        return CLLocationCoordinate2D(latitude: (latitude.0 + latitude.1) / 2,
                                      longitude: (longitude.0 + longitude.1) / 2)
    }
}

#Preview("Clair — membre") {
    NavigationStack {
        GroupDetailScreen(groupId: FakeData.ID.saintMichel)
            .offerDestination()
    }
    .environment(\.appContext, .instant)
}

#Preview("Sombre — pas membre") {
    NavigationStack {
        GroupDetailScreen(groupId: FakeData.ID.hochelaga)
            .offerDestination()
    }
    .environment(\.appContext, .instant)
    .preferredColorScheme(.dark)
}
