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
                    StateView(
                        state: viewModel.state,
                        empty: .init(title: "Aucun groupe près de toi", systemImage: GrenierSymbol.groups,
                                     message: "Aucun groupe de quartier n'est ouvert pour l'instant. Reviens bientôt."),
                        retry: { await viewModel.load() }
                    ) { items in
                        GroupList(items: items, viewModel: viewModel)
                    }
                } else {
                    ProgressView("Chargement…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .grenierBackground()
            .navigationTitle("Groupes")
            .profileToolbar()
            .navigationDestination(for: GroupRoute.self) { route in
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
                if !mine.isEmpty {
                    section(mine.count > 1 ? "Tes groupes" : "Ton groupe", items: mine)
                }
                if !others.isEmpty {
                    section("Groupes près de toi", items: others)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private func section(_ title: String, items: [GroupsViewModel.Item]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.texte)
                .accessibilityAddTraits(.isHeader)
            ForEach(items) { item in
                GroupRow(
                    item: item,
                    isPending: viewModel.pendingGroupIds.contains(item.id),
                    onJoin: { Task { await viewModel.join(groupId: item.id) } }
                )
            }
        }
    }
}

/// Un groupe : même contenu qu'un `GroupCard`, mais Rejoindre en `.glass` (une seule action principale par écran)
/// et le reste de la carte pousse la fiche du groupe.
private struct GroupRow: View {
    let item: GroupsViewModel.Item
    let isPending: Bool
    let onJoin: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 34

    private var group: NeighborhoodGroup { item.group }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            NavigationLink(value: GroupRoute(groupId: group.id)) {
                HStack(spacing: 12) {
                    AvatarStack(initials: [Self.initials(of: group.neighborhood)],
                                extraCount: max(group.householdCount - 1, 0),
                                size: avatarSize)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name)
                            .font(.headline)
                            .foregroundStyle(.texte)
                        Text(detailText)
                            .font(.subheadline)
                            .foregroundStyle(.texteSecondaire)
                    }
                    Spacer(minLength: 0)
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
        .sensoryFeedback(.success, trigger: item.isMember)
        .animation(reduceMotion ? nil : .smooth, value: item.isMember)
    }

    @ViewBuilder
    private var trailing: some View {
        if item.isMember {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.economie)
                .symbolEffect(.bounce, value: item.isMember)
                .accessibilityLabel("Tu es membre")
        } else {
            Button(action: onJoin) {
                if isPending {
                    ProgressView()
                } else {
                    Text("Rejoindre").fontWeight(.semibold)
                }
            }
            .buttonStyle(.glass)
            .tint(.grenier)
            .disabled(isPending)
            .accessibilityLabel("Rejoindre \(group.name)")
        }
    }

    /// « 27 familles · Hochelaga · rayon 900 m »
    private var detailText: String {
        let families = "\(group.householdCount) \(group.householdCount > 1 ? "familles" : "famille")"
        return "\(families) · \(group.neighborhood) · rayon \(GroupCard.distanceText(group.radiusMeters))"
    }

    /// « SM » pour Saint-Michel.
    static func initials(of name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" })
        return String(words.prefix(2).compactMap(\.first)).uppercased()
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
