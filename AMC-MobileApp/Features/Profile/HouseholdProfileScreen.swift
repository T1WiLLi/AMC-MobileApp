import SwiftUI

/// RQ-015 + RQ-020 : nom, taille et quartier du ménage ; demande de statut subventionné (privée).
/// Poussé depuis le Profil.
struct HouseholdProfileScreen: View {
    @State private var viewModel: HouseholdProfileViewModel

    init(viewModel: HouseholdProfileViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        StateView(state: viewModel.state, retry: { await viewModel.load() }) { _ in
            HouseholdForm(viewModel: viewModel)
        }
        .navigationTitle("Mon ménage")
        .navigationBarTitleDisplayMode(.inline)
        .seniorModeTextSize()
        .task { if viewModel.state.value == nil { await viewModel.load() } }
    }
}

/// Construit le ViewModel depuis l'environnement (dépôts + identité de démo).
struct HouseholdProfileLink: View {
    @Environment(\.appContext) private var context
    @Environment(\.householdPrivateStore) private var privateStore

    var body: some View {
        HouseholdProfileScreen(viewModel: HouseholdProfileViewModel(context: context, privateStore: privateStore))
    }
}

private struct HouseholdForm: View {
    @Bindable var viewModel: HouseholdProfileViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focus: Field?

    private enum Field { case name, postalCode, code }

    var body: some View {
        Form {
            summary
            householdSection
            neighborhoodSection
            subsidySection
            if let error = viewModel.saveError {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(error.title).font(.headline)
                            Text(error.message).font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: error.systemImage).foregroundStyle(.red)
                    }
                }
                .grenierTransition(.banner)
            }
        }
        .scrollContentBackground(.hidden)
        .grenierBackground()
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    focus = nil
                    Task { await viewModel.save() }
                } label: {
                    if viewModel.isSaving {
                        ProgressView().accessibilityLabel("Enregistrement en cours")
                    } else {
                        Label("Enregistrer", systemImage: "checkmark")
                    }
                }
                .disabled(!viewModel.canSave)
            }
        }
        .grenierHaptic(.success, trigger: viewModel.saveCount)
        .grenierHaptic(.success, trigger: viewModel.redeemCount)
        .grenierHaptic(.error, trigger: viewModel.saveError)
        .grenierAnimation(.smooth, value: viewModel.isSubsidized)
        .grenierAnimation(.smooth, value: viewModel.saveError)
    }

    // MARK: Résumé

    private var summary: some View {
        Section {
            HStack(spacing: 16) {
                Image(systemName: "house.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(width: 52, height: 52)
                    .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 14))
                    .symbolEffect(.bounce, value: viewModel.saveCount)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.trimmedName.isEmpty ? "Ton ménage" : viewModel.trimmedName)
                        .font(.headline)
                    Text(summaryLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
                if viewModel.saveCount > 0, !viewModel.hasChanges {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(Color.economie)
                        .symbolEffect(.bounce, value: viewModel.saveCount)
                        .accessibilityLabel("Enregistré")
                        .grenierTransition(.celebration)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private var summaryLine: String {
        let people = viewModel.size == 1 ? "1 personne" : "\(viewModel.size) personnes"
        guard let neighborhood = viewModel.neighborhood else { return people }
        return "\(people) · \(neighborhood.name)"
    }

    // MARK: Ménage

    private var householdSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Nom du ménage", text: $viewModel.name, prompt: Text("Famille Benali"))
                    .textContentType(.familyName)
                    .submitLabel(.next)
                    .focused($focus, equals: .name)
                    .onSubmit { focus = .postalCode }
                if let error = viewModel.nameError {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            Stepper(value: $viewModel.size, in: HouseholdProfileViewModel.sizeRange) {
                Label {
                    Text(viewModel.size == 1 ? "1 personne" : "\(viewModel.size) personnes")
                        .contentTransition(.numericText())
                        .monospacedDigit()
                } icon: {
                    Image(systemName: viewModel.size > 2 ? "person.3.fill" : viewModel.size == 2 ? "person.2.fill" : "person.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .grenierAnimation(.snappy, value: viewModel.size)
            .grenierHaptic(.selection, trigger: viewModel.size)
        } header: {
            Label("Ménage", systemImage: "person.2.fill")
        } footer: {
            Text("La taille aide l'organisateur à prévoir les quantités. Ton groupe voit le nom du ménage.")
        }
    }

    // MARK: Quartier

    private var neighborhoodSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Code postal", text: $viewModel.postalCode, prompt: Text("H2A 1B3"))
                    .textContentType(.postalCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .postalCode)
                    .onSubmit {
                        viewModel.postalCode = MontrealNeighborhood.formatted(postalCode: viewModel.postalCode)
                    }
                if let message = viewModel.postalMessage {
                    Label(message, systemImage: postalIcon)
                        .font(.footnote)
                        .foregroundStyle(postalColor)
                        .grenierTransition(.banner)
                }
            }
            .grenierAnimation(.smooth, value: viewModel.postalLookup)

            Picker(selection: $viewModel.neighborhood) {
                Text("Choisir…").tag(MontrealNeighborhood?.none)
                ForEach(MontrealNeighborhood.all) { neighborhood in
                    Text(neighborhood.name).tag(Optional(neighborhood))
                }
            } label: {
                Label("Quartier", systemImage: "map.fill")
            }
            .pickerStyle(.navigationLink)
        } header: {
            Label("Quartier", systemImage: "mappin.and.ellipse")
        } footer: {
            Text("On garde seulement ton quartier, jamais ton adresse. Il sert à te proposer les groupes près de chez toi.")
        }
    }

    private var postalIcon: String {
        switch viewModel.postalLookup {
        case .found: "checkmark.circle.fill"
        case .notServed: "location.slash"
        default: "exclamationmark.circle.fill"
        }
    }

    private var postalColor: Color {
        switch viewModel.postalLookup {
        case .found: .economie
        case .notServed: .secondary
        default: .red
        }
    }

    // MARK: Statut subventionné

    private var subsidySection: some View {
        Section {
            if viewModel.isSubsidized {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Statut subventionné actif").font(.headline)
                        if let code = viewModel.privateProfile?.referralCode {
                            Text("Code \(code)")
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.solidarite)
                        .symbolEffect(.bounce, value: viewModel.redeemCount)
                }
                .grenierTransition(.celebration)
                Button("Retirer mon statut", systemImage: "xmark.circle", role: .destructive) {
                    Task { await viewModel.withdrawSubsidy() }
                }
                .disabled(viewModel.isRedeeming)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Code d'organisme", text: $viewModel.codeInput, prompt: Text("ORG-CB-00427"))
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .code)
                        .submitLabel(.done)
                        .onSubmit { Task { await viewModel.redeemCode() } }
                    if let error = viewModel.codeError {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .grenierTransition(.banner)
                    }
                }
                .grenierHaptic(.warning, trigger: viewModel.codeError) { _, new in new != nil }
                Button {
                    focus = nil
                    Task { await viewModel.redeemCode() }
                } label: {
                    HStack {
                        Label("Valider le code", systemImage: "heart.fill")
                        if viewModel.isRedeeming {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .tint(Color.solidarite)
                .disabled(!viewModel.canRedeem)
            }
        } header: {
            Label("Aide alimentaire", systemImage: "heart.fill")
                .foregroundStyle(Color.solidarite)
        } footer: {
            Label("Seuls ton ménage et ton organisme voient ce statut. Ton groupe ne le sait jamais.",
                  systemImage: "lock.fill")
        }
    }
}

#Preview("Clair") {
    NavigationStack {
        HouseholdProfileScreen(viewModel: HouseholdProfileViewModel(
            context: .demo, privateStore: FakeHouseholdPrivateStore(behavior: .realistic)))
    }
}

#Preview("Sombre, subventionné") {
    NavigationStack {
        HouseholdProfileScreen(viewModel: HouseholdProfileViewModel(
            context: .instant,
            privateStore: FakeHouseholdPrivateStore(profiles: [
                FakeData.ID.aminaHousehold: HouseholdPrivate(isSubsidized: true, referralCode: "ORG-CB-04271"),
            ])))
    }
    .preferredColorScheme(.dark)
}

#Preview("AX5") {
    NavigationStack {
        HouseholdProfileScreen(viewModel: HouseholdProfileViewModel(
            context: .instant, privateStore: FakeHouseholdPrivateStore()))
    }
    .dynamicTypeSize(.accessibility5)
}

#Preview("Hors ligne") {
    NavigationStack {
        HouseholdProfileScreen(viewModel: HouseholdProfileViewModel(
            repositories: .fake(behavior: .failing()), privateStore: FakeHouseholdPrivateStore(),
            userId: FakeData.ID.amina, householdId: FakeData.ID.aminaHousehold))
    }
}
