import SwiftUI

/// T-191 : « Familles membres » de la fiche d'un groupe. Chaque famille a son avatar (initiales, sinon une maison),
/// son nom et son rôle. Le créateur du groupe, et lui seul, a un menu « Retirer du groupe » (confirmé) sur les
/// autres familles ; jamais sur la sienne.
///
///     GroupFamiliesSection(model: families) { await viewModel.load() }
struct GroupFamiliesSection: View {
    let model: GroupFamiliesViewModel
    /// Le groupe a changé (famille retirée) : la fiche relit ses membres et son compteur.
    var onChange: () async -> Void = {}

    @Environment(\.groupTheme) private var theme
    @State private var pendingRemoval: GroupFamiliesViewModel.Family?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupsSectionHeader(title: String(localized: "Familles membres"), systemImage: GrenierSymbol.groups,
                                tint: theme.accent, count: model.state.value?.count)
            switch model.state {
            case .idle, .loading:
                card(for: Self.placeholders)
                    .redacted(reason: .placeholder)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Chargement des familles")
            case .failed(let error):
                errorCard(error)
            case .empty:
                emptyCard
            case .loaded(let families):
                card(for: families)
            }
        }
        .sensoryFeedback(.success, trigger: model.removalCount)
        .confirmationDialog(
            dialogTitle,
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { family in
            Button("Retirer du groupe", role: .destructive) {
                Task {
                    if await model.remove(family) { await onChange() }
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: { _ in
            Text("Cette famille ne verra plus le groupe, ses lots ni ses cueillettes. Ses parts déjà réservées restent valides. Elle pourra revenir si le groupe l'accepte.")
        }
        .alert(
            model.actionError?.title ?? "",
            isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } }),
            presenting: model.actionError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }

    // MARK: - États

    private func card(for families: [GroupFamiliesViewModel.Family]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(families.enumerated()), id: \.element.id) { index, family in
                if index > 0 { Divider().padding(.leading, 64) }
                FamilyRow(family: family, canRemove: model.canRemove(family),
                          isRemoving: model.removingIds.contains(family.householdId),
                          accent: theme.accent) { pendingRemoval = family }
                    .grenierAppear(index: index)
            }
        }
        .padding(.vertical, 4)
        .background(Color.surface, in: .rect(cornerRadius: 24))
        .animation(.smooth, value: families.map(\.id))
    }

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "house.and.flag.fill")
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.accent)
                .accessibilityHidden(true)
            Text("Aucune famille pour l'instant")
                .font(.headline)
                .foregroundStyle(.texte)
            Text("Les familles qui rejoindront le groupe apparaîtront ici.")
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .grenierCard()
        .accessibilityElement(children: .combine)
    }

    private func errorCard(_ error: AppError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
            Text(error.message)
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
            Button("Réessayer", systemImage: "arrow.clockwise") { Task { await model.load() } }
                .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
    }

    private var dialogTitle: String {
        guard let family = pendingRemoval else { return "" }
        return String(localized: "Retirer \(FamilyRow.displayName(of: family)) du groupe ?")
    }

    private static let placeholders = (0..<3).map {
        GroupFamiliesViewModel.Family(householdId: "placeholder-\($0)", name: "Famille Placeholder", role: .member, isMine: false)
    }
}

// MARK: - Ligne

private struct FamilyRow: View {
    let family: GroupFamiliesViewModel.Family
    let canRemove: Bool
    let isRemoving: Bool
    let accent: Color
    let remove: () -> Void

    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 40

    static func displayName(of family: GroupFamiliesViewModel.Family) -> String {
        family.name ?? String(localized: "Une famille du quartier")
    }

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.displayName(of: family))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.texte)
                if let caption {
                    Label(caption.text, systemImage: caption.systemImage)
                        .font(.caption)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.texteSecondaire)
                }
            }
            Spacer(minLength: 0)
            if canRemove {
                Menu {
                    Button("Retirer du groupe", systemImage: "person.fill.xmark", role: .destructive, action: remove)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.texteSecondaire)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel(String(localized: "Actions pour \(Self.displayName(of: family))"))
                .accessibilityHint("Permet de retirer cette famille du groupe.")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .opacity(isRemoving ? 0.4 : 1)
        .overlay { if isRemoving { ProgressView() } }
        .contextMenu {
            if canRemove {
                Button("Retirer du groupe", systemImage: "person.fill.xmark", role: .destructive, action: remove)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Initiales du ménage (« Famille Benali » → « B ») ; une maison quand le nom est illisible.
    private var avatar: some View {
        ZStack {
            Circle().fill(accent.opacity(0.15))
            if let initials = family.name.flatMap(GroupDetailViewModel.initials(ofHouseholdName:)) {
                Text(initials)
                    .font(.subheadline.bold())
                    .fontDesign(.rounded)
                    .foregroundStyle(accent)
            } else {
                Image(systemName: GrenierSymbol.home)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accent)
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .accessibilityHidden(true)
    }

    private var caption: (text: String, systemImage: String)? {
        if family.isMine {
            return (String(localized: "Ta famille"), "house.fill")
        }
        if family.role == .coordinator {
            return (String(localized: "Coordonnateur"), "star.circle.fill")
        }
        return nil
    }

    private var accessibilityLabel: String {
        let name = Self.displayName(of: family)
        if family.isMine { return String(localized: "\(name), ta famille") }
        if family.role == .coordinator { return String(localized: "\(name), coordonnateur du groupe") }
        return name
    }
}

#Preview("Créateur") {
    @Previewable @State var model = GroupFamiliesViewModel(
        repositories: .fake(behavior: .instant), groupId: FakeData.ID.villerayKitchen,
        householdId: FakeData.ID.aminaHousehold, userId: FakeData.ID.amina
    )
    ScrollView { GroupFamiliesSection(model: model).padding() }
        .grenierBackground()
        .task { await model.load() }
}

#Preview("Membre") {
    @Previewable @State var model = GroupFamiliesViewModel(
        repositories: .fake(behavior: .instant), groupId: FakeData.ID.villerayKitchen,
        householdId: "household-voisin-1", userId: "voisin-1"
    )
    ScrollView { GroupFamiliesSection(model: model).padding() }
        .grenierBackground()
        .task { await model.load() }
}
