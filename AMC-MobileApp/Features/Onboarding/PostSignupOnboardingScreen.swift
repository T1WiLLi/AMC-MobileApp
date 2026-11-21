import SwiftUI

/// Onboarding juste après l'inscription (T-156) : goûts → quartier → ménage → « Tout est prêt », puis l'app.
/// Montré par `SessionContextGate` quand `AppContext.needsOnboarding` est vrai.
struct PostSignupOnboardingScreen: View {
    @State private var model: PostSignupOnboardingViewModel
    /// Appelé une fois l'onboarding fini (ou remis à plus tard), avec l'id du ménage enregistré.
    private let onFinish: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focus: Field?

    private enum Field { case postalCode, name }

    init(model: PostSignupOnboardingViewModel, onFinish: @escaping (String) -> Void = { _ in }) {
        _model = State(initialValue: model)
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.loadState {
                case .loaded:
                    stepScroll
                case .failed(let error):
                    ErrorStateView(error: error) { await model.load() }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .idle, .loading, .empty:
                    ProgressView("Préparation de ton espace…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .grenierBackground()
            .toolbar { toolbar }
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { if model.loadState.value == nil { await model.load() } }
        .grenierHaptic(.selection, trigger: model.favoriteCategories)
        .grenierHaptic(.selection, trigger: model.dietaryPreferences)
        .grenierHaptic(.success, trigger: model.step == .done)
    }

    // MARK: Barre du haut

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.canGoBack {
            ToolbarItem(placement: .topBarLeading) {
                Button("Retour", systemImage: "chevron.backward") {
                    focus = nil
                    withAnimation(animation) { model.back() }
                }
            }
        }
        if model.step != .done, model.loadState.value != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Plus tard") {
                    Task {
                        if await model.skip() { onFinish(model.savedHouseholdId ?? "") }
                    }
                }
                .disabled(model.isSaving)
                .accessibilityHint("Ouvre l'app tout de suite. Tu pourras régler tes préférences dans ton profil.")
            }
        }
    }

    // MARK: Étapes

    private var stepScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                stepContent
                    .id(model.step)
                    .transition(stepTransition)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .animation(animation, value: model.step)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.step != .done {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Étape \(model.stepNumber) sur \(model.stepCount)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.grenier)
                        .contentTransition(.numericText())
                    ProgressView(value: model.progress)
                        .tint(.grenier)
                        .accessibilityHidden(true)
                }
            }
            Image(systemName: model.step.systemImage)
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .symbolEffect(.bounce, value: reduceMotion ? 0 : model.step.rawValue)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            Text(model.step.title)
                .font(.largeTitle.bold())
                .foregroundStyle(Color.texte)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(model.step.subtitle)
                .font(.body)
                .foregroundStyle(Color.texteSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(animation, value: model.step)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .tastes: tastesStep
        case .neighborhood: neighborhoodStep
        case .household: householdStep
        case .done: doneStep
        }
    }

    // MARK: 1. Goûts

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 150), spacing: 12)]
    }

    private var tastesStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Catégories aimées", systemImage: "heart.fill")
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(Product.Category.allCases.enumerated()), id: \.element) { index, category in
                        ChoiceTile(
                            title: category.title,
                            systemImage: ProductIcon.symbol(for: category),
                            isSelected: model.isSelected(category)
                        ) {
                            withAnimation(animation) { model.toggle(category) }
                        }
                        .grenierAppear(index: index)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Restrictions alimentaires", systemImage: "fork.knife")
                Text("Facultatif. On te signale les lots qui y répondent.")
                    .font(.footnote)
                    .foregroundStyle(Color.texteSecondaire)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(DietaryTag.allCases, id: \.self) { tag in
                        ChoiceTile(
                            title: PreferencesViewModel.title(of: tag),
                            systemImage: PreferencesViewModel.systemImage(of: tag),
                            isSelected: model.isSelected(tag)
                        ) {
                            withAnimation(animation) { model.toggle(tag) }
                        }
                    }
                }
            }
        }
    }

    // MARK: 2. Quartier

    private var neighborhoodStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            card {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Code postal", systemImage: "envelope.fill")
                        .font(.headline)
                        .foregroundStyle(Color.texte)
                    TextField("Code postal", text: $model.postalCode, prompt: Text("H2A 1B3"))
                        .font(.title3.monospaced())
                        .textContentType(.postalCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focus, equals: .postalCode)
                        .onSubmit { model.postalCode = MontrealNeighborhood.formatted(postalCode: model.postalCode) }
                        .padding(12)
                        .background(AppTheme.fond, in: .rect(cornerRadius: 12))
                    if let message = model.postalMessage {
                        Label(message, systemImage: postalIcon)
                            .font(.footnote)
                            .foregroundStyle(postalColor)
                            .fixedSize(horizontal: false, vertical: true)
                            .grenierTransition(.banner)
                    }
                }
                .grenierAnimation(.smooth, value: model.postalLookup)
            }

            card {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Ou choisis ton quartier", systemImage: "map.fill")
                        .font(.headline)
                        .foregroundStyle(Color.texte)
                    Picker(selection: $model.neighborhood) {
                    Text("Choisir…").tag(MontrealNeighborhood?.none)
                    ForEach(MontrealNeighborhood.all) { neighborhood in
                        Text(neighborhood.name).tag(Optional(neighborhood))
                    }
                    } label: {
                        Text("Quartier")
                    }
                    .pickerStyle(.menu)
                    .tint(.grenier)
                    .labelsHidden()
                }
            }

            if let neighborhood = model.neighborhood {
                Label {
                    Text("Tu seras proche des groupes de **\(neighborhood.name)**.")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.economie)
                        .symbolEffect(.bounce, value: reduceMotion ? "" : neighborhood.name)
                }
                .font(.subheadline)
                .foregroundStyle(Color.texte)
                .grenierTransition(.banner)
            }
        }
        .animation(animation, value: model.neighborhood)
    }

    private var postalIcon: String {
        switch model.postalLookup {
        case .found: "checkmark.circle.fill"
        case .notServed: "location.slash"
        default: "exclamationmark.circle.fill"
        }
    }

    private var postalColor: Color {
        switch model.postalLookup {
        case .found: .economie
        case .notServed: .secondary
        default: .red
        }
    }

    // MARK: 3. Ménage

    private var householdStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            card {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Nom du ménage", systemImage: "house.fill")
                        .font(.headline)
                        .foregroundStyle(Color.texte)
                    TextField("Nom du ménage", text: $model.householdName, prompt: Text("Famille Benali"))
                        .font(.title3)
                        .textContentType(.familyName)
                        .submitLabel(.done)
                        .focused($focus, equals: .name)
                        .padding(12)
                        .background(AppTheme.fond, in: .rect(cornerRadius: 12))
                    if let error = model.nameError {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Ton groupe de quartier voit ce nom.")
                            .font(.footnote)
                            .foregroundStyle(Color.texteSecondaire)
                    }
                }
            }

            card {
                Stepper(value: $model.householdSize, in: PostSignupOnboardingViewModel.sizeRange) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Personnes")
                                .font(.headline)
                            Text(FrenchPlural.count(model.householdSize, "personne"))
                                .font(.title2.bold())
                                .fontDesign(.rounded)
                                .monospacedDigit()
                                .contentTransition(.numericText(value: Double(model.householdSize)))
                                .foregroundStyle(Color.grenier)
                        }
                    } icon: {
                        Image(systemName: sizeSymbol)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.grenier)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .foregroundStyle(Color.texte)
                }
                .grenierAnimation(.snappy, value: model.householdSize)
                .grenierHaptic(.selection, trigger: model.householdSize)
            }

            if let error = model.saveError {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .grenierTransition(.banner)
            }
        }
    }

    private var sizeSymbol: String {
        switch model.householdSize {
        case 1: "person.fill"
        case 2: "person.2.fill"
        default: "person.3.fill"
        }
    }

    // MARK: 4. Fini

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            SummaryRow(title: "Tu aimes", value: model.tastesSummary, systemImage: "heart.fill")
                .grenierAppear(index: 0)
            SummaryRow(title: "Restrictions", value: model.dietarySummary, systemImage: "fork.knife")
                .grenierAppear(index: 1)
            SummaryRow(title: "Quartier", value: model.neighborhood?.name ?? "", systemImage: "mappin.and.ellipse")
                .grenierAppear(index: 2)
            SummaryRow(title: "Ménage", value: model.householdSummary, systemImage: "person.2.fill")
                .grenierAppear(index: 3)
        }
    }

    // MARK: Action principale

    private var bottomBar: some View {
        Button(action: primaryAction) {
            HStack(spacing: 8) {
                if model.isSaving {
                    ProgressView()
                        .tint(Color.onAccent)
                }
                Text(primaryTitle)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(model.canContinue ? Color.onAccent : Color.texteSecondaire)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .tint(.grenier)
        .disabled(!model.canContinue)
        .accessibilityHint(primaryHint)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private var primaryTitle: String {
        switch model.step {
        case .tastes, .neighborhood: String(localized: "Continuer")
        case .household: model.isSaving ? String(localized: "Enregistrement…") : String(localized: "Créer mon ménage")
        case .done: String(localized: "Ouvrir mon tableau de bord")
        }
    }

    private var primaryHint: String {
        switch model.step {
        case .tastes: String(localized: "Passe au quartier")
        case .neighborhood:
            model.canContinue ? String(localized: "Passe au ménage") : String(localized: "Entre ton code postal ou choisis un quartier")
        case .household: String(localized: "Enregistre tes préférences et ton ménage")
        case .done: String(localized: "Ouvre le portail Familles")
        }
    }

    private func primaryAction() {
        focus = nil
        if model.step == .done {
            onFinish(model.savedHouseholdId ?? "")
            return
        }
        if model.step == .neighborhood {
            model.postalCode = MontrealNeighborhood.formatted(postalCode: model.postalCode)
        }
        Task { await model.next() }
    }

    // MARK: Briques

    private var animation: Animation? { reduceMotion ? .easeInOut(duration: 0.2) : .smooth }

    private var stepTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }

    private func sectionTitle(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.title3.bold())
            .foregroundStyle(Color.texte)
            .symbolRenderingMode(.hierarchical)
            .accessibilityAddTraits(.isHeader)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: .rect(cornerRadius: 20))
    }
}

// MARK: - Tuile à cocher

/// Carte opaque tapable, cochée quand elle est choisie (catégories, restrictions).
private struct ChoiceTile: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isSelected ? Color.onAccent : Color.grenier)
                        .frame(width: 40, height: 40)
                        .background(isSelected ? Color.grenier : Color.grenier.opacity(0.12), in: .circle)
                        .accessibilityHidden(true)
                    Spacer(minLength: 8)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.grenier : Color.texteSecondaire)
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.texte)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.surface, in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(isSelected ? Color.grenier : Color.clear, lineWidth: 2)
            }
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(isSelected ? String(localized: "Touche pour retirer") : String(localized: "Touche pour choisir"))
    }
}

// MARK: - Ligne du récapitulatif

private struct SummaryRow: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Color.texteSecondaire)
                Text(value)
                    .font(.headline)
                    .foregroundStyle(Color.texte)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
private enum OnboardingPreview {
    static func model(step: PostSignupOnboardingViewModel.Step = .tastes) -> PostSignupOnboardingViewModel {
        let user = AppUser(
            id: "user-nouveau", displayName: "Amina Benali", photoURL: nil, language: .french, roles: [.family],
            neighborhood: "", dietaryPreferences: [], seniorMode: false, householdId: "household-nouveau",
            vendorId: nil, onboardingCompleted: false
        )
        let household = Household(id: "household-nouveau", name: "Ménage de Amina", size: 1, geohash: "", userIds: [user.id])
        var repositories = AppRepositories.fake(behavior: .instant)
        repositories.users = FakeUserRepository(users: [user], households: [household])
        return PostSignupOnboardingViewModel(repositories: repositories, userId: user.id, householdId: household.id)
    }
}

#Preview("Goûts") {
    PostSignupOnboardingScreen(model: OnboardingPreview.model())
}

#Preview("Goûts, sombre") {
    PostSignupOnboardingScreen(model: OnboardingPreview.model())
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    PostSignupOnboardingScreen(model: OnboardingPreview.model())
        .dynamicTypeSize(.accessibility5)
}
#endif
