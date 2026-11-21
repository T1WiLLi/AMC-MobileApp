import SwiftUI

/// Route vers la fiche d'un groupe (F2), poussée depuis la liste des groupes.
struct GroupRoute: Hashable, Sendable {
    let groupId: String
}

/// Onglet Groupes : les groupes de quartier publics, les tiens d'abord. Tap → fiche du groupe (F2).
/// Pas d'action principale : la création de groupe n'est pas encore prévue.
struct GroupsScreen: View {
    @Environment(\.appContext) private var context
    @State private var viewModel: GroupsViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    switch viewModel.state {
                    case .idle, .loading:
                        GroupsLoadingSkeleton()
                    case .empty:
                        GroupsIllustratedState(
                            scene: GroupsSymbolScene(
                                systemImage: "map.fill",
                                satellites: [
                                    .init(systemImage: "house.fill", tint: .economie, degrees: -145),
                                    .init(systemImage: "person.fill.questionmark", tint: .grenier, degrees: -35),
                                    .init(systemImage: GrenierSymbol.offers, tint: .grenier, degrees: 145)
                                ]
                            ),
                            title: "Aucun groupe près de toi",
                            message: "Aucun groupe de quartier n'est ouvert pour l'instant. Reviens bientôt."
                        ) {
                            Button {
                                Task { await viewModel.load() }
                            } label: {
                                Label("Actualiser", systemImage: "arrow.clockwise")
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.glass)
                            .tint(.grenier)
                            .controlSize(.large)
                        }
                    case .failed(let error):
                        GroupsErrorState(error: error, retry: { await viewModel.load() })
                    case .loaded(let items):
                        GroupList(items: items, viewModel: viewModel)
                    }
                } else {
                    GroupsLoadingSkeleton()
                }
            }
            .grenierBackground()
            .navigationTitle("Groupes")
            .profileToolbar()
            .toolbar {
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
            .refreshable { await viewModel?.load() }
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
        }
        .task {
            guard viewModel == nil else { return }
            let model = GroupsViewModel(repositories: context.repositories, householdId: context.householdId)
            viewModel = model
            await model.load()
        }
    }
}

private struct GroupList: View {
    let items: [GroupsViewModel.Item]
    let viewModel: GroupsViewModel

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

                VStack(alignment: .leading, spacing: 12) {
                    GroupsSectionHeader(
                        title: mine.count > 1 ? "Tes groupes" : "Ton groupe",
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

                if !others.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        GroupsSectionHeader(
                            title: "Groupes près de toi",
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
                onJoin: { Task { await viewModel.join(groupId: item.id) } }
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
        GroupsStatTile(value: "\(myGroupCount)", caption: myGroupCount > 1 ? "tes groupes" : "ton groupe",
                       systemImage: "checkmark.seal.fill", tint: .economie)
        GroupsStatTile(value: "\(nearbyCount)", caption: "à rejoindre",
                       systemImage: "location.fill", tint: .grenier)
        GroupsStatTile(value: "\(familyCount)", caption: familyCount > 1 ? "familles" : "famille",
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

/// Un groupe : même contenu qu'un `GroupCard`, mais Rejoindre en `.glass` (une seule action principale par écran)
/// et le reste de la carte pousse la fiche du groupe.
private struct GroupRow: View {
    let item: GroupsViewModel.Item
    let isPending: Bool
    let onJoin: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var group: NeighborhoodGroup { item.group }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            NavigationLink(value: GroupRoute(groupId: group.id)) {
                HStack(spacing: 12) {
                    GroupRowIcon(isMember: item.isMember)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name)
                            .font(.headline)
                            .foregroundStyle(.texte)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) { meta }
                            VStack(alignment: .leading, spacing: 2) { meta }
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.texteSecondaire)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(group.name), \(detailText)\(item.isMember ? ", tu es membre" : "")")
            .accessibilityHint("Ouvre la fiche du groupe.")

            trailing
        }
        .grenierCard(padding: 14)
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

    @ViewBuilder
    private var meta: some View {
        GroupsMetaLabel(text: familiesText, systemImage: "person.2.fill", tint: .solidarite)
        GroupsMetaLabel(text: group.neighborhood, systemImage: "mappin", tint: .grenier)
        GroupsMetaLabel(text: GroupCard.distanceText(group.radiusMeters), systemImage: "circle.dashed", tint: .economie)
    }

    @ViewBuilder
    private var trailing: some View {
        if item.isMember {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.economie)
                .groupsBounce(value: item.isMember)
                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                .accessibilityLabel("Tu es membre")
        } else {
            Button(action: onJoin) {
                if isPending {
                    ProgressView()
                } else {
                    Label("Rejoindre", systemImage: "person.badge.plus")
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.glass)
            .tint(.grenier)
            .disabled(isPending)
            .accessibilityLabel("Rejoindre \(group.name)")
        }
    }

    private var familiesText: String {
        FrenchPlural.count(group.householdCount, "famille")
    }

    /// « 27 familles · Hochelaga · rayon 900 m »
    private var detailText: String {
        "\(familiesText) · \(group.neighborhood) · rayon \(GroupCard.distanceText(group.radiusMeters))"
    }
}

/// Tuile du groupe dans la liste : une icône de quartier (les initiales du quartier ressemblaient à des membres).
private struct GroupRowIcon: View {
    let isMember: Bool
    @ScaledMetric(relativeTo: .title3) private var side: CGFloat = 44

    var body: some View {
        let tint: Color = isMember ? .economie : .grenier
        Image(systemName: isMember ? "checkmark.seal.fill" : GrenierSymbol.groups)
            .font(.title3)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: min(side, 72), height: min(side, 72))
            .background(tint.opacity(0.12), in: .circle)
            .accessibilityHidden(true)
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
