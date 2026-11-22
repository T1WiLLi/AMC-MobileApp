import SwiftUI

/// Route vers la fiche d'un groupe (F2), poussée depuis la liste des groupes.
struct GroupRoute: Hashable, Sendable {
    let groupId: String
}

/// Onglet Groupes : tes groupes (publics et privés), puis les groupes publics du plus proche au plus loin.
/// Tap → fiche du groupe (F2). B-056 : « Rejoindre avec un code » (invitation à un groupe privé, ou code
/// d'un groupe public), aussi ouvert par un lien `grenier://join/<code>` ou `https://grenier.app/join/<code>`.
struct GroupsScreen: View {
    @Environment(\.appContext) private var context
    @Environment(InviteLinkRouter.self) private var inviteLinks: InviteLinkRouter?
    /// Rejoindre, quitter ou créer un groupe change le groupe actif : l'Accueil suit (contexte rechargé).
    @Environment(SessionContextStore.self) private var contextStore: SessionContextStore?
    @State private var viewModel: GroupsViewModel?
    @State private var path = NavigationPath()
    /// Feuille « Rejoindre avec un code » ouverte, avec le code d'un lien reçu s'il y en a un.
    @State private var joinCode: JoinCodeRequest?
    /// B-059 : feuille « Créer un groupe ».
    @State private var isCreatingGroup = false
    /// Ouvert en feuille (« Trouver un groupe » des états vides, FB-15) : bouton Fermer en tête.
    var showsCloseButton = false
    @Environment(\.dismiss) private var dismiss

    /// Contenu selon l'état du chargement (découpé pour le vérificateur de types).
    @ViewBuilder
    private func stateContent(_ viewModel: GroupsViewModel) -> some View {
        switch viewModel.state {
        case .idle, .loading:
            GroupsLoadingSkeleton()
        case .empty:
            emptyState(viewModel)
        case .failed(let error):
            GroupsErrorState(error: error, retry: { await viewModel.load() })
        case .loaded(let items):
            GroupList(items: items, viewModel: viewModel,
                      onCreateGroup: { isCreatingGroup = true })
        }
    }

    /// Aucun groupe autour : en créer un est l'action principale (FB-10).
    private func emptyState(_ viewModel: GroupsViewModel) -> some View {
        let scene = GroupsSymbolScene(systemImage: "map.fill", satellites: Self.emptySatellites)
        let title = String(localized: "Aucun groupe près de toi")
        let message = String(localized: "Aucun groupe de quartier n'est ouvert pour l'instant. Lance le tien : tes voisins pourront le rejoindre.")
        return GroupsIllustratedState(scene: scene, title: title, message: message) {
            GroupsEmptyActions(
                onCreate: { isCreatingGroup = true },
                onRefresh: { await viewModel.load() }
            )
        }
    }

    private static let emptySatellites: [GroupsSymbolScene.Satellite] = [
        GroupsSymbolScene.Satellite(systemImage: "house.fill", tint: Color.economie, degrees: -145),
        GroupsSymbolScene.Satellite(systemImage: "person.fill.questionmark", tint: Color.grenier, degrees: -35),
        GroupsSymbolScene.Satellite(systemImage: GrenierSymbol.offers, tint: Color.grenier, degrees: 145)
    ]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let viewModel {
                    stateContent(viewModel)
                } else {
                    GroupsLoadingSkeleton()
                }
            }
            .grenierBackground()
            .navigationTitle("Groupes")
            .profileToolbar()
            .infoToolbarButton(.group)
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Fermer", systemImage: "xmark", role: .close) {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Ajouter un groupe", systemImage: "plus") {
                        Button("Rejoindre avec un code", systemImage: "ticket") {
                            joinCode = JoinCodeRequest(code: "")
                        }
                        .accessibilityHint("Entre dans un groupe avec une invitation reçue")
                        Button("Créer un groupe", systemImage: "person.3.sequence.fill") {
                            isCreatingGroup = true
                        }
                        .accessibilityHint("Ton ménage en devient le premier membre")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        FamilyMapScreen()
                    } label: {
                        Label("Carte du quartier", systemImage: GrenierSymbol.map)
                    }
                    .accessibilityHint("Groupes, points de cueillette et producteurs autour de chez toi")
                }
            }
            .grenierZoomDestination(for: GroupRoute.self) { route in
                GroupDetailScreen(groupId: route.groupId)
            }
            .offerDestination()
            .refreshable {
                await viewModel?.load()
                await contextStore?.reload()
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
            .sheet(item: $joinCode) { request in
                JoinWithCodeSheet(repositories: context.repositories, householdId: context.householdId,
                                  code: request.code) { group in
                    Task {
                        await viewModel?.didJoin(group)
                        await contextStore?.reload(preferring: group.id)
                    }
                    path.append(GroupRoute(groupId: group.id))
                }
            }
            .sheet(isPresented: $isCreatingGroup) {
                CreateGroupSheet(repositories: context.repositories, userId: context.userId,
                                 householdId: context.householdId) { group in
                    Task {
                        await viewModel?.didJoin(group)
                        await contextStore?.reload(preferring: group.id)
                    }
                    path.append(GroupRoute(groupId: group.id))
                }
            }
        }
        // Lien d'invitation reçu par l'app (B-058), même avant que cet onglet soit chargé.
        .onChange(of: inviteLinks?.pendingCode, initial: true) { _, code in
            guard code != nil, let code = inviteLinks?.consume() else { return }
            joinCode = JoinCodeRequest(code: code)
        }
        .task { await startViewModel() }
    }

    /// Crée le modèle au premier passage, puis suit les groupes du ménage (FB-22) tant que l'onglet vit :
    /// quand un autre membre rejoint ou quitte un groupe, la liste et l'Accueil suivent.
    private func startViewModel() async {
        let model: GroupsViewModel
        if let existing = viewModel {
            model = existing
        } else {
            model = GroupsViewModel(repositories: context.repositories, householdId: context.householdId)
            viewModel = model
            await model.load()
        }
        let store = contextStore
        await model.observeHouseholdGroups { await store?.reload() }
    }
}

/// Ouverture de la feuille « Rejoindre avec un code ».
private struct JoinCodeRequest: Identifiable {
    let id = UUID()
    let code: String
}

private struct GroupList: View {
    let items: [GroupsViewModel.Item]
    let viewModel: GroupsViewModel
    /// FB-10 : « Créer un groupe » bien visible, pas seulement dans le menu +.
    let onCreateGroup: () -> Void
    @Environment(SessionContextStore.self) private var contextStore: SessionContextStore?

    var body: some View {
        let mine = items.filter(\.isMember)
        let others = items.filter { !$0.isMember }
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GroupsHeroCard(
                    myGroupCount: mine.count,
                    nearbyCount: others.count,
                    familyCount: items.reduce(0) { $0 + $1.group.householdCount }
                )
                .guidedTourAnchor(.groups)

                VStack(alignment: .leading, spacing: 12) {
                    GroupsSectionHeader(
                        title: mine.count > 1 ? String(localized: "Tes groupes") : String(localized: "Ton groupe"),
                        systemImage: "checkmark.seal.fill",
                        tint: .economie,
                        count: mine.isEmpty ? nil : mine.count
                    )
                    if mine.isEmpty {
                        NoGroupYetCard()
                            .grenierTransition(.cardAppear)
                    }
                    rows(mine)
                }

                CreateGroupCard(hasGroup: !mine.isEmpty, action: onCreateGroup)
                    .grenierTransition(.cardAppear)

                if !others.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        GroupsSectionHeader(
                            title: String(localized: "Groupes près de toi"),
                            systemImage: "location.circle.fill",
                            tint: .grenier,
                            count: others.count
                        )
                        rows(others)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .grenierScrollEdge()
        .grenierAnimation(.smooth, value: mine.map(\.id))
    }

    private func rows(_ items: [GroupsViewModel.Item]) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            GroupRow(
                item: item,
                isPending: viewModel.pendingGroupIds.contains(item.id),
                onJoin: {
                    Task {
                        await viewModel.join(groupId: item.id)
                        await contextStore?.reload(preferring: item.id)
                    }
                }
            )
            .grenierTransition(.cardAppear)
            .grenierAppear(index: index)
        }
    }
}

// MARK: - En-tête illustré

/// Tête d'écran : une scène de quartier en symboles, la promesse en une phrase et trois chiffres clés.
private struct GroupsHeroCard: View {
    let myGroupCount: Int
    let nearbyCount: Int
    let familyCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { scene; pitch }
                VStack(alignment: .leading, spacing: 8) { scene; pitch }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { tiles }
                VStack(spacing: 8) { tiles }
            }
        }
        .grenierCard(padding: 18)
    }

    private var scene: some View {
        GroupsSymbolScene(
            systemImage: GrenierSymbol.groups,
            satellites: [
                .init(systemImage: "house.fill", tint: .economie, degrees: -150),
                .init(systemImage: GrenierSymbol.offers, tint: .grenier, degrees: -30),
                .init(systemImage: GrenierSymbol.impact, tint: .economie, degrees: 40),
                .init(systemImage: GrenierSymbol.solidarity, tint: .solidarite, degrees: 140)
            ],
            diameter: 76,
            badgeBackground: .fond,
            isAnimating: true
        )
    }

    private var pitch: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Groupes de quartier", systemImage: "mappin.and.ellipse")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color.grenier)
            Text("Achète en gros avec tes voisins")
                .font(.title3.bold())
                .foregroundStyle(.texte)
            Text("Plus vous êtes de familles, plus le prix baisse.")
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var tiles: some View {
        GroupsStatTile(value: "\(myGroupCount)", caption: myGroupCount > 1 ? String(localized: "tes groupes") : String(localized: "ton groupe"),
                       systemImage: "checkmark.seal.fill", tint: .economie)
        GroupsStatTile(value: "\(nearbyCount)", caption: String(localized: "à rejoindre"),
                       systemImage: "location.fill", tint: .grenier)
        GroupsStatTile(value: "\(familyCount)", caption: FrenchPlural.word(familyCount, "famille", plural: "familles"),
                       systemImage: "person.2.fill", tint: .solidarite)
    }
}

/// Aucun groupe à soi : une invitation douce à en rejoindre un plus bas.
private struct NoGroupYetCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pas encore de groupe")
                    .font(.headline)
                    .foregroundStyle(.texte)
                Label("Rejoins un groupe près de toi, juste en dessous", systemImage: "hand.point.down.fill")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            }
            Spacer(minLength: 0)
        }
        .grenierCard(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

/// FB-10 : créer son propre groupe doit se trouver sans chercher. Carte visible dans la liste,
/// en plus de l'entrée du menu + de la barre.
private struct CreateGroupCard: View {
    let hasGroup: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "person.3.sequence.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
                    .frame(width: 48, height: 48)
                    .background(Color.grenier.opacity(0.12), in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hasGroup ? "Un autre quartier ?" : "Pas de groupe qui te convient ?")
                        .font(.headline)
                        .foregroundStyle(.texte)
                    Text("Crée ton groupe : ton ménage en devient le premier membre, puis invite tes voisins.")
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            Button(action: action) {
                Label("Créer un groupe", systemImage: "plus.circle.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.grenier)
            .controlSize(.large)
            .accessibilityHint("Ton ménage en devient le premier membre")
        }
        .grenierCard(padding: 16)
    }
}

// MARK: - Squelette de chargement

/// Chargement : la forme de l'écran en `.redacted`, qui pulse doucement (fixe sous Reduce Motion).
private struct GroupsLoadingSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Circle().frame(width: 76, height: 76)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Groupes de quartier")
                            Text("Achète en gros avec tes voisins").font(.title3.bold())
                        }
                    }
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 16).frame(height: 76)
                        }
                    }
                }
                .grenierCard(padding: 18)
                Label("Groupes près de toi", systemImage: "location.circle.fill")
                    .font(.title3.bold())
                ForEach(0..<4, id: \.self) { _ in
                    HStack(spacing: 12) {
                        Circle().frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nom du groupe de quartier").font(.headline)
                            Text("27 familles · Quartier · 900 m").font(.subheadline)
                        }
                        Spacer(minLength: 0)
                    }
                    .grenierCard(padding: 14)
                }
            }
            .foregroundStyle(.texteSecondaire.opacity(0.35))
            .redacted(reason: .placeholder)
            .padding(.horizontal, 16)
        }
        .scrollDisabled(true)
        .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.55]) { content, opacity in
            content.opacity(opacity)
        } animation: { _ in
            .easeInOut(duration: 0.9)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement des groupes")
    }
}

// MARK: - Ligne d'un groupe

/// Un groupe (FB-12) : sa bannière et sa photo en tête, son nom en entier, puis deux pastilles en icônes.
/// Rejoindre en `.glass` (une seule action principale par écran) ; pour un membre, la carte pousse la fiche du groupe.
private struct GroupRow: View {
    let item: GroupsViewModel.Item
    let isPending: Bool
    let onJoin: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .headline) private var photoSize: CGFloat = 56
    @ScaledMetric(relativeTo: .headline) private var bannerHeight: CGFloat = 92

    private var group: NeighborhoodGroup { item.group }
    private var avatarSide: CGFloat { min(photoSize, 84) }
    private var neighborhood: String { MontrealNeighborhood.displayName(for: group.neighborhood) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // T-187 : un non-membre ouvre la fiche publique du groupe (T-172) : avis, lots en consultation.
            NavigationLink(value: GroupRoute(groupId: group.id)) {
                summary
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.isMember ? Text("\(group.name), \(detailText), tu es membre")
                                              : Text("\(group.name), \(detailText)"))
            .accessibilityHint("Ouvre la fiche du groupe.")
            if !item.isMember {
                joinButton
                    .padding([.horizontal, .bottom], 14)
            }
        }
        .background(Color.surface)
        .clipShape(.rect(cornerRadius: theme.cornerRadius))
        // La fiche du groupe sort de la carte entière en zoom (T-123).
        .grenierZoomSource(GroupRoute(groupId: group.id))
        .contextMenu {
            Label(detailText, systemImage: GrenierSymbol.groups)
            if !item.isMember {
                Button(action: onJoin) {
                    Label("Rejoindre \(group.name)", systemImage: "person.badge.plus")
                }
                .disabled(isPending)
            }
        }
        .sensoryFeedback(.success, trigger: item.isMember)
        .animation(reduceMotion ? nil : .smooth, value: item.isMember)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            banner
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // Pas de coupure au trait d'union (« Côte-des- / Neiges ») : traits insécables, deux lignes au plus.
                    Text(Self.unbreakable(group.name))
                        .font(.headline)
                        .foregroundStyle(.texte)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.texteSecondaire)
                }
                // Pastilles en ligne, qui passent à la ligne une à une quand la place manque
                // (au lieu de tout empiler en colonne dès qu'un nom de quartier est long).
                PickupFlowLayout(spacing: 6) { chips }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.top, avatarSide / 2 + 8)
            .padding(.bottom, 14)
        }
        .contentShape(.rect)
    }

    /// Bannière du groupe (dégradé Grenier s'il n'en a pas), photo qui la chevauche et badges d'état.
    private var banner: some View {
        GroupBannerImage(group: group)
            .frame(maxWidth: .infinity)
            .frame(height: min(bannerHeight, 140))
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 40)
            }
            .overlay(alignment: .topTrailing) { statusBadge.padding(10) }
            .overlay(alignment: .bottomLeading) {
                GroupAvatarView(group: group, size: avatarSide, showsRing: true)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    .offset(x: 14, y: avatarSide / 2)
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 6) {
            if !group.isPublic {
                BannerBadge(systemImage: "lock.fill", text: String(localized: "Privé"))
            }
            if item.isMember {
                BannerBadge(systemImage: "checkmark.seal.fill", text: String(localized: "Membre"), tint: .economie)
                    .groupsBounce(value: item.isMember)
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var chips: some View {
        GroupsChip(text: "\(group.householdCount)", systemImage: "person.2.fill", tint: .solidarite)
        if !neighborhood.isEmpty {
            GroupsChip(text: Self.unbreakable(neighborhood), systemImage: "mappin", tint: .grenier)
        }
        if let distance = item.distanceText {
            // B-056 : distance du ménage au groupe (la liste est triée du plus proche au plus loin).
            GroupsChip(text: distance, systemImage: "location.fill", tint: .economie)
        }
    }

    private var joinButton: some View {
        Button(action: onJoin) {
            Group {
                if isPending {
                    ProgressView()
                } else {
                    Label("Rejoindre", systemImage: "person.badge.plus")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .tint(.grenier)
        .disabled(isPending)
        .accessibilityLabel("Rejoindre \(group.name)")
    }

    private var familiesText: String {
        FrenchPlural.count(group.householdCount, "famille")
    }

    /// « 27 familles · Hochelaga · à 1,4 km · rayon 900 m » (« groupe privé » en tête s'il l'est), pour VoiceOver.
    private var detailText: String {
        let distance = item.distanceText.map { " · \($0)" } ?? ""
        let base = String(localized: "\(familiesText) · \(neighborhood)\(distance) · rayon \(GroupCard.distanceText(group.radiusMeters))")
        return group.isPublic ? base : String(localized: "Groupe privé · \(base)")
    }

    /// Remplace les traits d'union par des traits insécables (U+2011) : le texte ne se coupe plus au tiret.
    static func unbreakable(_ text: String) -> String {
        text.replacingOccurrences(of: "-", with: "\u{2011}")
    }
}

/// Pastille compacte d'une ligne de groupe : icône teintée et une valeur courte.
/// Icône et texte serrés (4 pt) : trois pastilles tiennent sur une ligne.
private struct GroupsChipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

private struct GroupsChip: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(.texte)
                .lineLimit(1)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
        .font(.footnote.weight(.semibold))
        .labelStyle(GroupsChipLabelStyle())
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: .capsule)
    }
}

/// Badge posé sur la bannière (Privé, Membre) : matériau pour rester lisible sur n'importe quelle image.
private struct BannerBadge: View {
    let systemImage: String
    let text: String
    var tint: Color = .texte

    var body: some View {
        Label {
            Text(text).foregroundStyle(.texte)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: .capsule)
    }
}

#Preview("Clair") {
    GroupsScreen()
        .environment(\.appContext, .instant)
}

#Preview("Sombre") {
    GroupsScreen()
        .environment(\.appContext, .instant)
        .preferredColorScheme(.dark)
}

/// Actions de l'état vide de la liste : créer un groupe (principal), actualiser.
private struct GroupsEmptyActions: View {
    let onCreate: () -> Void
    let onRefresh: () async -> Void

    var body: some View {
        Button(action: onCreate) {
            Label("Créer un groupe", systemImage: "plus.circle.fill")
                .fontWeight(.semibold)
        }
        .buttonStyle(.glassProminent)
        .tint(.grenier)
        .controlSize(.large)
        Button {
            Task { await onRefresh() }
        } label: {
            Label("Actualiser", systemImage: "arrow.clockwise")
                .fontWeight(.semibold)
        }
        .buttonStyle(.glass)
        .tint(.grenier)
        .controlSize(.large)
    }
}
