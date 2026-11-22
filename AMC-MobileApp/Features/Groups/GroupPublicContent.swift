import SwiftUI

/// T-172 (FB-13) : fiche publique d'un groupe, pour un ménage qui n'en fait pas partie.
/// Avant, toucher un groupe dont on n'était pas membre affichait « Action non permise » (lecture des parts
/// refusée par les règles). Le visiteur voit maintenant ce qui donne envie d'entrer : bannière et photo,
/// quartier, familles, lots ouverts en aperçu, coordination, visibilité, puis une seule action principale :
/// « Rejoindre le groupe » (public) ou « Demander une invitation » (privé). Une fois membre, `GroupDetailScreen`
/// bascule tout seul sur la fiche complète.
struct GroupPublicContent: View {
    @Environment(\.groupTheme) private var theme
    @Environment(\.appContext) private var context
    @Environment(SessionContextStore.self) private var contextStore: SessionContextStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let content: GroupDetailViewModel.Content
    let viewModel: GroupDetailViewModel

    /// Groupe privé : feuille « Rejoindre avec un code ».
    @State private var isJoiningWithCode = false
    @State private var showsNavigationTitle = false

    /// Aperçu : les premiers lots seulement, le reste se découvre une fois membre.
    static let previewLimit = 3

    private var group: NeighborhoodGroup { content.group }
    private var neighborhood: String? { NeighborhoodName.display(group.neighborhood) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupHeroHeader(group: group, editor: nil) { _ in }

                VStack(alignment: .leading, spacing: 24) {
                    header
                    keyFigures
                    coordinationCard
                    openOrdersPreview
                    benefits
                    if !group.isPublic { PrivateGroupNote(isMember: false) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
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
        .safeAreaInset(edge: .bottom) { joinBar }
        .sheet(isPresented: $isJoiningWithCode) {
            JoinWithCodeSheet(repositories: context.repositories, householdId: context.householdId) { joined in
                Task {
                    await viewModel.load()
                    await contextStore?.reload(preferring: joined.id)
                }
            }
        }
    }

    // MARK: En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label((neighborhood ?? String(localized: "Groupe de quartier")).uppercased(),
                      systemImage: "mappin.circle.fill")
                    .font(.caption.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.accent)
                Spacer(minLength: 0)
                VisibilityBadge(isPublic: group.isPublic)
            }
            Label {
                Text(theme.displayName ?? group.name)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.texte)
            } icon: {
                Image(systemName: theme.emblem)
                    .font(.title.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.accent)
                    .accessibilityHidden(true)
            }
            .accessibilityAddTraits(.isHeader)
            if let welcome = theme.welcomeMessage {
                Text(welcome)
                    .font(.body)
                    .foregroundStyle(.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Chiffres clés

    private var keyFigures: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { keyFigureTiles }
            VStack(spacing: 8) { keyFigureTiles }
        }
    }

    @ViewBuilder
    private var keyFigureTiles: some View {
        let orders = content.openOrders.count
        GroupsStatTile(value: "\(group.householdCount)", caption: FrenchPlural.word(group.householdCount, "famille"),
                       systemImage: "person.2.fill", tint: .solidarite)
        GroupsStatTile(value: "\(orders)", caption: FrenchPlural.word(orders, "lot ouvert", plural: "lots ouverts"),
                       systemImage: GrenierSymbol.offers, tint: theme.accent)
        GroupsStatTile(value: GroupCard.distanceText(group.radiusMeters), caption: String(localized: "de rayon"),
                       systemImage: "circle.dashed", tint: .economie)
    }

    // MARK: Coordination

    private var coordinationCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(content.coordinatorName.map { String(localized: "Coordonné par \($0)") }
                     ?? String(localized: "Coordonné par des voisins bénévoles"))
                    .font(.headline)
                    .foregroundStyle(.texte)
                Text("Ils lancent les commandes et choisissent le point de cueillette du quartier.")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .grenierCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: Lots ouverts

    @ViewBuilder
    private var openOrdersPreview: some View {
        let orders = content.openOrders
        VStack(alignment: .leading, spacing: 12) {
            GroupsSectionHeader(title: String(localized: "En ce moment dans le groupe"),
                                systemImage: GrenierSymbol.offers, tint: theme.accent, count: orders.count)
            if orders.isEmpty {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pas de lot ouvert pour l'instant")
                            .font(.headline)
                            .foregroundStyle(.texte)
                        Text("Rejoins le groupe pour être averti dès qu'une commande est lancée.")
                            .font(.subheadline)
                            .foregroundStyle(.texteSecondaire)
                    }
                } icon: {
                    Image(systemName: "bell.badge.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(theme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .grenierCard()
                .accessibilityElement(children: .combine)
            } else {
                ForEach(orders.prefix(Self.previewLimit)) { summary in
                    NavigationLink(value: OfferRoute(offerId: summary.offer.id)) {
                        OfferCard(offer: summary.offer, product: summary.product, vendor: summary.vendor,
                                  committedShares: summary.committedShares,
                                  committedHouseholds: summary.committedHouseholds)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Ouvre la fiche du lot.")
                }
                if orders.count > Self.previewLimit {
                    Label(String(localized: "Et \(FrenchPlural.count(orders.count - Self.previewLimit, "autre lot", plural: "autres lots")) pour les membres"),
                          systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(theme.accent)
                }
            }
        }
    }

    // MARK: Pourquoi rejoindre

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupsSectionHeader(title: String(localized: "Pourquoi rejoindre"), systemImage: "sparkles",
                                tint: .economie)
            VStack(alignment: .leading, spacing: 14) {
                benefit("chart.line.downtrend.xyaxis", .economie,
                        String(localized: "Le prix baisse à chaque famille"),
                        String(localized: "Plus le groupe commande, plus le palier descend pour tout le monde."))
                benefit("figure.walk", .solidarite,
                        String(localized: "Cueillette à deux pas"),
                        neighborhood.map { String(localized: "Un point de cueillette dans \($0), à distance de marche.") }
                            ?? String(localized: "Un point de cueillette dans ton quartier, à distance de marche."))
                benefit("hand.raised.fill", theme.accent,
                        String(localized: "Gratuit et sans engagement"),
                        String(localized: "Tu choisis tes parts lot par lot et tu peux quitter quand tu veux."))
            }
            .grenierCard()
        }
    }

    private func benefit(_ symbol: String, _ tint: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(minWidth: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.texte)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Action principale

    @ViewBuilder
    private var joinBar: some View {
        VStack(spacing: 8) {
            if group.isPublic {
                Button {
                    Task {
                        await viewModel.join()
                        await contextStore?.reload(preferring: group.id)
                    }
                } label: {
                    Group {
                        if viewModel.isUpdatingMembership {
                            ProgressView()
                        } else {
                            Label("Rejoindre le groupe", systemImage: "person.badge.plus")
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
                .accessibilityHint("Ton ménage rejoint \(group.name) et voit tous ses lots.")
            } else {
                // Groupe privé : on demande une invitation à un voisin qui en fait partie, ou on entre son code.
                ShareLink(item: Self.invitationRequest(for: group)) {
                    Label("Demander une invitation", systemImage: "envelope.badge.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(theme.accent)
                .controlSize(.large)
                .accessibilityHint("Envoie une demande à un voisin qui fait partie du groupe.")
                Button {
                    isJoiningWithCode = true
                } label: {
                    Label("J'ai déjà une invitation", systemImage: "ticket.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Message partagé pour demander une invitation à un groupe privé.
    static func invitationRequest(for group: NeighborhoodGroup) -> String {
        String(localized: "Salut ! Peux-tu m'envoyer une invitation pour rejoindre « \(group.name) » sur LeGrenier ? Merci !")
    }
}

/// « Public » (globe) ou « Privé » (cadenas).
private struct VisibilityBadge: View {
    let isPublic: Bool

    var body: some View {
        Label(isPublic ? String(localized: "Public") : String(localized: "Privé"),
              systemImage: isPublic ? "globe.americas.fill" : "lock.fill")
            .font(.caption.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isPublic ? Color.economie : Color.texteSecondaire)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background((isPublic ? Color.economie : Color.texteSecondaire).opacity(0.12), in: .capsule)
            .accessibilityLabel(isPublic ? String(localized: "Groupe public") : String(localized: "Groupe privé"))
    }
}

#if DEBUG
#Preview("Visiteur — groupe public") {
    NavigationStack {
        GroupDetailScreen(groupId: FakeData.ID.hochelaga)
            .offerDestination()
    }
    .environment(\.appContext, .instant)
}

#Preview("Visiteur — groupe privé, sombre") {
    NavigationStack {
        GroupDetailScreen(groupId: FakeData.ID.villerayKitchen)
            .offerDestination()
    }
    .environment(\.appContext, AppContext(
        repositories: .fake(behavior: .instant), userId: "user-visiteur",
        householdId: "household-visiteur", groupId: nil, vendorId: ""
    ))
    .preferredColorScheme(.dark)
}
#endif
