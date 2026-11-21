import SwiftUI

/// S-07 « Ce que le groupe veut » (T-108) : la demande cumulée du groupe, anonyme, et les envies de ma famille.
/// Poussée depuis la fiche d'un groupe (`GroupDetailScreen`), dont elle garde le thème (B-034).
struct GroupWishesScreen: View {
    let groupId: String

    @Environment(\.appContext) private var context
    @Environment(\.groupTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: GroupWishesViewModel?
    @State private var draft: GroupWishesViewModel.Draft?

    var body: some View {
        Group {
            if let viewModel {
                switch viewModel.state {
                case .idle, .loading:
                    GroupsLoadingScene(title: "Chargement des envies…", systemImage: "basket.fill")
                case .failed(let error):
                    GroupsErrorState(error: error, retry: { await viewModel.load() })
                case .empty:
                    content(GroupWishesViewModel.Content(demand: [], myWishes: []), viewModel: viewModel)
                case .loaded(let content):
                    self.content(content, viewModel: viewModel)
                }
            } else {
                GroupsLoadingScene(title: "Chargement des envies…", systemImage: "basket.fill")
            }
        }
        .grenierBackground()
        .navigationTitle("Ce que le groupe veut")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Ajouter une envie", systemImage: "plus") { draft = .init() }
                    .disabled(viewModel?.state.value == nil)
            }
        }
        .sheet(item: $draft) { draft in
            if let viewModel {
                GroupWishEditor(draft: draft, isSaving: viewModel.isSaving) { saved in
                    await viewModel.save(saved)
                }
                .tint(theme.accent)
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
        .task {
            if viewModel == nil {
                viewModel = GroupWishesViewModel(repositories: context.repositories, groupId: groupId,
                                                 householdId: context.householdId)
            }
            await viewModel?.load()
            await viewModel?.observe()
        }
    }

    private func content(_ content: GroupWishesViewModel.Content, viewModel: GroupWishesViewModel) -> some View {
        List {
            Section {
                if content.demand.isEmpty {
                    Label("Personne n'a encore dit ce qu'il veut. Lance le mouvement !", systemImage: "sparkles")
                        .foregroundStyle(.texteSecondaire)
                } else {
                    ForEach(content.demand) { demand in
                        DemandRow(demand: demand)
                    }
                }
            } header: {
                GroupsSectionHeader(title: "Le groupe", systemImage: "person.3.fill", tint: theme.accent)
            } footer: {
                Text("Totaux anonymes : personne ne voit ce que ta famille a demandé.")
            }

            Section {
                if content.myWishes.isEmpty {
                    Button {
                        draft = .init()
                    } label: {
                        Label("Dire ce que ma famille veut", systemImage: "plus.circle.fill")
                    }
                } else {
                    ForEach(content.myWishes) { wish in
                        Button {
                            draft = .init(wish)
                        } label: {
                            MyWishRow(wish: wish)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Modifier cette envie")
                        .swipeActions {
                            Button("Retirer", systemImage: "trash", role: .destructive) {
                                Task { await viewModel.remove(wish) }
                            }
                        }
                    }
                }
            } header: {
                GroupsSectionHeader(title: "Ma famille", systemImage: "house.fill", tint: .economie,
                                    count: content.myWishes.count)
            }

            if !content.myWishes.isEmpty {
                Section {
                    NavigationLink {
                        MatchingOffersScreen(groupId: groupId)
                    } label: {
                        Label("Offres qui correspondent à vos souhaits", systemImage: "sparkle.magnifyingglass")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .animation(reduceMotion ? nil : .smooth, value: content)
    }
}

extension GroupWishesViewModel.Draft: Identifiable {
    var id: String { wishId ?? "nouvelle" }
}

// MARK: - Lignes

private struct DemandRow: View {
    let demand: GroupDemand
    @Environment(\.groupTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ProductIcon.symbol(for: demand.category))
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.accent)
                .frame(width: 36, height: 36)
                .background(theme.accent.opacity(0.12), in: .rect(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(demand.category.title)
                    .font(.headline)
                Label(GroupWishesViewModel.householdsText(demand.householdCount), systemImage: "person.2.fill")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .contentTransition(.numericText(value: Double(demand.householdCount)))
            }
            Spacer(minLength: 8)
            Text(GroupWishesViewModel.quantityText(demand.totalQuantity, unit: demand.unit))
                .priceStyle(.headline)
                .contentTransition(.numericText(value: demand.totalQuantity))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MyWishRow: View {
    let wish: GroupWish

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ProductIcon.symbol(for: wish.category))
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.economie)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(wish.category.title)
                    .font(.headline)
                Text(wish.frequency.title)
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            }
            Spacer(minLength: 8)
            Text(GroupWishesViewModel.quantityText(wish.quantity, unit: wish.unit))
                .priceStyle(.headline)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.texteSecondaire)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Éditeur

private struct GroupWishEditor: View {
    @State var draft: GroupWishesViewModel.Draft
    let isSaving: Bool
    let onSave: (GroupWishesViewModel.Draft) async -> Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Catégorie", selection: $draft.category) {
                    ForEach(Product.Category.allCases, id: \.self) { category in
                        Label(category.title, systemImage: ProductIcon.symbol(for: category)).tag(category)
                    }
                }
                Section("Quantité") {
                    Stepper(value: $draft.quantity, in: 0.5...10_000, step: draft.unit == .kilogram ? 1 : 0.5) {
                        Text(GroupWishesViewModel.quantityText(draft.quantity, unit: draft.unit))
                            .priceStyle(.headline)
                    }
                    Picker("Unité", selection: $draft.unit) {
                        ForEach(MeasureUnit.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Picker("Rythme", selection: $draft.frequency) {
                    ForEach(GroupWish.Frequency.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            .navigationTitle(draft.isNew ? "Nouvelle envie" : "Modifier l'envie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        Task { if await onSave(draft) { dismiss() } }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview("Clair") {
    NavigationStack {
        GroupWishesScreen(groupId: FakeData.ID.saintMichel)
    }
    .environment(\.appContext, .instant)
}

#Preview("Sombre") {
    NavigationStack {
        GroupWishesScreen(groupId: FakeData.ID.saintMichel)
    }
    .environment(\.appContext, .instant)
    .preferredColorScheme(.dark)
}
