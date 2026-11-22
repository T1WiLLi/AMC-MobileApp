import SwiftUI

/// S-08 « Mes disponibilités » (T-109) : ce que le vendeur a, avant même de créer un lot.
/// Poussée depuis l'onglet Lots ; « Créer un lot » ouvre le TierEditor prérempli (zones, produit, date limite).
struct VendorSuppliesScreen: View {
    let onCreateLot: (VendorSupply) -> Void
    private let repositories: AppRepositories
    private let vendorId: String

    @State private var model: VendorSuppliesViewModel
    @State private var draft: VendorSuppliesViewModel.Draft?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(repositories: AppRepositories, vendorId: String, onCreateLot: @escaping (VendorSupply) -> Void) {
        _model = State(initialValue: VendorSuppliesViewModel(repositories: repositories, vendorId: vendorId))
        self.onCreateLot = onCreateLot
        self.repositories = repositories
        self.vendorId = vendorId
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .grenierBackground()
            .navigationTitle("Mes disponibilités")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        InterestedGroupsScreen(repositories: repositories, vendorId: vendorId, onCreateLot: onCreateLot)
                    } label: {
                        Label("Groupes intéressés", systemImage: "person.3.sequence")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Ajouter une disponibilité", systemImage: "plus") { draft = model.newDraft() }
                }
            }
            .sheet(item: $draft) { draft in
                SupplyEditor(draft: draft, isSaving: model.isSaving) { await model.save($0) }
            }
            .alert(model.actionError?.title ?? "", isPresented: Binding(
                get: { model.actionError != nil },
                set: { if !$0 { model.actionError = nil } }
            ), presenting: model.actionError) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.message)
            }
            .task {
                await model.load()
                await model.observe()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Chargement des disponibilités…")
        case .empty:
            ContentUnavailableView {
                Label("Aucune disponibilité", systemImage: "tray")
                    .symbolEffect(.bounce, options: .nonRepeating, isActive: !reduceMotion)
            } description: {
                Text("Dis ce que tu peux livrer et quand : les groupes qui en veulent le verront, même sans lot.")
            } actions: {
                Button("Ajouter une disponibilité", systemImage: "plus") { draft = model.newDraft() }
                    .buttonStyle(.glassProminent)
            }
        case .failed, .loaded:
            StateView(state: model.state, retry: { await model.load() }) { supplies in
                list(supplies)
            }
        }
    }

    private func list(_ supplies: [VendorSupply]) -> some View {
        List {
            Section {
                ForEach(supplies) { supply in
                    SupplyRow(supply: supply, isPast: model.isPast(supply),
                              edit: { draft = .init(supply) }, createLot: { onCreateLot(supply) })
                    .swipeActions {
                        Button("Retirer", systemImage: "trash", role: .destructive) {
                            Task { await model.remove(supply) }
                        }
                    }
                }
            } footer: {
                Text("Touche une disponibilité pour la modifier, glisse pour la retirer.")
            }
        }
        .scrollContentBackground(.hidden)
        .animation(reduceMotion ? nil : .smooth, value: supplies)
    }
}

// MARK: - Ligne

private struct SupplyRow: View {
    let supply: VendorSupply
    let isPast: Bool
    let edit: () -> Void
    let createLot: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: ProductIcon.symbol(for: supply.category))
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
                    .frame(width: 36, height: 36)
                    .background(Color.grenier.opacity(0.12), in: .rect(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(supply.category.title)
                        .font(.headline)
                    Label(VendorSuppliesViewModel.periodText(from: supply.availableFrom, to: supply.availableTo),
                          systemImage: isPast ? "calendar.badge.exclamationmark" : "calendar")
                        .font(.subheadline)
                        .foregroundStyle(isPast ? Color.red : .texteSecondaire)
                    Label("\(supply.servedZones.count) \(FrenchPlural.word(supply.servedZones.count, "zone", plural: "zones"))",
                          systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                }
                Spacer(minLength: 8)
                Text(GroupWishesViewModel.quantityText(supply.quantity, unit: supply.unit))
                    .priceStyle(.headline)
            }
            .contentShape(.rect)
            .onTapGesture(perform: edit)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Modifier cette disponibilité")
            .accessibilityAction { edit() }

            if !isPast {
                Button(action: createLot) {
                    Label("Créer un lot à paliers", systemImage: "square.stack.3d.up.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Éditeur

private struct SupplyEditor: View {
    @State var draft: VendorSuppliesViewModel.Draft
    let isSaving: Bool
    let onSave: (VendorSuppliesViewModel.Draft) async -> Bool

    @Environment(\.dismiss) private var dismiss

    private var zonesText: Binding<String> {
        Binding(
            get: { draft.servedZones.joined(separator: ", ") },
            set: { text in
                draft.servedZones = text.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    .filter { !$0.isEmpty }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $draft.category) {
                        ForEach(Product.Category.allCases, id: \.self) { category in
                            Label(category.title, systemImage: ProductIcon.symbol(for: category)).tag(category)
                        }
                    } label: {
                        Label("Catégorie", systemImage: ProductIcon.symbol(for: draft.category))
                            .contentTransition(.symbolEffect(.replace))
                    }
                } header: {
                    sectionHeader("Produit", systemImage: "shippingbox.fill")
                }
                .listRowBackground(Color.surface)

                Section {
                    Stepper(value: $draft.quantity, in: 1...1_000_000, step: draft.quantity >= 100 ? 10 : 1) {
                        Text(GroupWishesViewModel.quantityText(draft.quantity, unit: draft.unit))
                            .priceStyle(.headline)
                            .foregroundStyle(.texte)
                            .contentTransition(.numericText(value: draft.quantity))
                    }
                    Picker("Unité", selection: $draft.unit) {
                        ForEach(MeasureUnit.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    sectionHeader("Quantité disponible", systemImage: "scalemass.fill")
                }
                .listRowBackground(Color.surface)

                Section {
                    DatePicker(selection: $draft.availableFrom, displayedComponents: .date) {
                        Label("Du", systemImage: "calendar")
                    }
                    DatePicker(selection: $draft.availableTo, in: draft.availableFrom..., displayedComponents: .date) {
                        Label("Au", systemImage: "calendar.badge.clock")
                    }
                } header: {
                    sectionHeader("Période", systemImage: "calendar")
                }
                .listRowBackground(Color.surface)

                Section {
                    TextField("f25d, f25e", text: zonesText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(.texte)
                } header: {
                    sectionHeader("Zones desservies", systemImage: "mappin.and.ellipse")
                } footer: {
                    Label("Préfixes geohash séparés par des virgules ; préremplis avec les zones de ton profil.",
                          systemImage: "info.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.texteSecondaire)
                }
                .listRowBackground(Color.surface)
            }
            .scrollContentBackground(.hidden)
            .symbolRenderingMode(.hierarchical)
            .scrollDismissesKeyboard(.interactively)
            .grenierBackground()
            .navigationTitle(draft.isNew ? "Nouvelle disponibilité" : "Modifier")
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
                    .tint(.grenier)
                    .disabled(isSaving)
                }
            }
        }
        // Une feuille ne reçoit pas le thème de la fenêtre : on le repose (teinte Grenier, plus de bleu système).
        .appThemed()
        .presentationDetents([.large])
        .presentationBackground(Color.fond)
    }

    private func sectionHeader(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            Text(title)
                .foregroundStyle(.texte)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Color.grenier)
        }
        .font(.subheadline.weight(.semibold))
        .textCase(nil)
    }
}

#Preview("Clair") {
    NavigationStack {
        VendorSuppliesScreen(repositories: .fake(behavior: .instant), vendorId: FakeData.ID.fermeRive) { _ in }
    }
}

#Preview("Sombre") {
    NavigationStack {
        VendorSuppliesScreen(repositories: .fake(behavior: .instant), vendorId: FakeData.ID.fermeRive) { _ in }
    }
    .preferredColorScheme(.dark)
}

#Preview("Nouvelle disponibilité — clair") {
    Color.clear.sheet(isPresented: .constant(true)) {
        SupplyEditor(draft: .init(zones: ["f25d", "f25e"]), isSaving: false) { _ in true }
    }
}

#Preview("Nouvelle disponibilité — sombre, grand texte") {
    Color.clear.sheet(isPresented: .constant(true)) {
        SupplyEditor(draft: .init(zones: ["f25d", "f25e"]), isSaving: false) { _ in true }
    }
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility2)
}
