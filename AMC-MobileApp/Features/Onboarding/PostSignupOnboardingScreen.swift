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
    @Environment(\.scenePhase) private var scenePhase

    @FocusState private var addressFocused: Bool

    private enum Field { case postalCode, name, addressPostalCode }

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
        .grenierHaptic(.success, trigger: model.step == .waiting)
        // T-159 : en attente du propriétaire, on regarde régulièrement (et au retour dans l'app) s'il a répondu.
        .task(id: model.step) {
            guard model.step == .waiting else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, model.step == .waiting, !model.joinDeclined else { return }
                await model.checkJoin()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, model.step == .waiting else { return }
            Task { await model.checkJoin() }
        }
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
        case .joinChoice: joinChoiceStep
        case .waiting: waitingStep
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

            addressCard

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

    /// T-159 : adresse du ménage (numéro, rue, code postal), privée.
    private var addressCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Label("Adresse (facultatif)", systemImage: "mappin.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Color.texte)
                    .symbolRenderingMode(.hierarchical)
                AddressField("Numéro et rue", text: $model.streetLine, model: model.addressCheck,
                             prompt: "1234 rue Jarry Est", boxed: true, isFocused: $addressFocused)
                TextField("Code postal", text: $model.postalCode, prompt: Text("H2R 1A1"))
                    .font(.title3)
                    .textContentType(.postalCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focus, equals: .addressPostalCode)
                    .padding(12)
                    .background(AppTheme.fond, in: .rect(cornerRadius: 12))
                    .accessibilityLabel("Code postal")
                if let error = model.addressError {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label("Pour retrouver ta famille si elle est déjà inscrite. Seuls les membres de ton ménage voient ton adresse.", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.texteSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: 3 bis. Rejoindre ou créer (T-159)

    private var joinChoiceStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            card {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "house.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.grenier)
                        .frame(width: 52, height: 52)
                        .background(Color.grenier.opacity(0.12), in: .circle)
                        .symbolEffect(.bounce, value: reduceMotion ? 0 : 1)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ménage trouvé à ton adresse")
                            .font(.subheadline)
                            .foregroundStyle(Color.texteSecondaire)
                        Text(model.matchName)
                            .font(.title2.bold())
                            .foregroundStyle(Color.texte)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .grenierAppear(index: 0)

            VStack(alignment: .leading, spacing: 10) {
                benefitRow("Mêmes groupes de quartier", systemImage: "person.3.fill")
                benefitRow("Mêmes commandes et réservations", systemImage: "cart.fill")
                benefitRow("Une seule cueillette, par n'importe qui du ménage", systemImage: "qrcode")
            }
            .grenierAppear(index: 1)

            Button {
                Task { await model.createOwnHousehold() }
            } label: {
                Label("Créer un nouveau ménage", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
            .disabled(model.isSaving)
            .accessibilityHint("Crée un ménage séparé, même à cette adresse")
            .grenierAppear(index: 2)

            saveErrorLabel
        }
    }

    private func benefitRow(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            Text(title)
                .font(.body)
                .foregroundStyle(Color.texte)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
        }
    }

    // MARK: 3 ter. En attente du propriétaire (T-159)

    private var waitingStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            card {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: model.joinDeclined ? "xmark.circle.fill" : "hourglass")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(model.joinDeclined ? Color.secondary : Color.grenier)
                        .frame(width: 52, height: 52)
                        .background((model.joinDeclined ? Color.secondary : Color.grenier).opacity(0.12), in: .circle)
                        .symbolEffect(.pulse, isActive: !reduceMotion && !model.joinDeclined)
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.matchName)
                            .font(.title3.bold())
                            .foregroundStyle(Color.texte)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(model.joinDeclined
                             ? String(localized: "Ta demande n'a pas été acceptée. Crée ton propre ménage pour continuer.")
                             : String(localized: "En attente du propriétaire du ménage…"))
                            .font(.subheadline)
                            .foregroundStyle(Color.texteSecondaire)
                            .fixedSize(horizontal: false, vertical: true)
                        if let sent = model.joinRequest?.createdAt, !model.joinDeclined {
                            Text("Envoyée \(sent, format: .relative(presentation: .named))")
                                .font(.footnote)
                                .foregroundStyle(Color.texteSecondaire)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .animation(animation, value: model.joinDeclined)

            if !model.joinDeclined {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { cancelJoinButton; createInsteadButton }
                    VStack(spacing: 12) { cancelJoinButton; createInsteadButton }
                }
            }

            saveErrorLabel
        }
    }

    private var cancelJoinButton: some View {
        Button(role: .cancel) {
            Task { await model.cancelJoin() }
        } label: {
            Label("Annuler la demande", systemImage: "xmark")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glass)
        .disabled(model.isSaving)
    }

    private var createInsteadButton: some View {
        Button {
            Task { await model.createOwnHousehold() }
        } label: {
            Label("Créer mon ménage", systemImage: "plus.circle")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glass)
        .disabled(model.isSaving)
        .accessibilityHint("Annule la demande et crée un ménage à toi")
    }

    @ViewBuilder
    private var saveErrorLabel: some View {
        if let error = model.saveError {
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .grenierTransition(.banner)
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
        case .household: model.isSaving ? String(localized: "Enregistrement…") : String(localized: "Continuer")
        case .joinChoice: String(localized: "Rejoindre \(model.matchName)")
        case .waiting:
            model.joinDeclined ? String(localized: "Créer mon ménage")
                : model.isCheckingJoin ? String(localized: "Vérification…") : String(localized: "Vérifier maintenant")
        case .done: String(localized: "Ouvrir mon tableau de bord")
        }
    }

    private var primaryHint: String {
        switch model.step {
        case .tastes: String(localized: "Passe au quartier")
        case .neighborhood:
            model.canContinue ? String(localized: "Passe au ménage") : String(localized: "Entre ton code postal ou choisis un quartier")
        case .household: String(localized: "Enregistre tes préférences et ton ménage")
        case .joinChoice: String(localized: "Envoie une demande au propriétaire du ménage")
        case .waiting:
            model.joinDeclined ? String(localized: "Crée un ménage à toi") : String(localized: "Regarde si le propriétaire a accepté")
        case .done: String(localized: "Ouvre le portail Familles")
        }
    }

    private func primaryAction() {
        focus = nil
        addressFocused = false
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

/// Carte opaque tapable, cochée quand elle est choisie (catégories, restrictions, type de vendeur T-158).
struct ChoiceTile: View {
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

/// Ligne de récapitulatif (onboarding Familles et producteur).
struct SummaryRow: View {
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

    /// T-159 : demande envoyée à la Famille Benali, en attente.
    static func waitingModel() -> PostSignupOnboardingViewModel {
        let user = AppUser(
            id: "user-karim", displayName: "Karim Benali", photoURL: nil, language: .french, roles: [.family],
            neighborhood: "Villeray", dietaryPreferences: [], seniorMode: false, householdId: "household-user-karim",
            vendorId: nil, onboardingCompleted: false, pendingHouseholdId: "household-amina"
        )
        let own = Household(id: "household-user-karim", name: "Ménage de Karim", size: 1, geohash: "", userIds: [user.id])
        let amina = Household(id: "household-amina", name: "Famille Benali", size: 4, geohash: "f25du", userIds: ["amina"], ownerId: "amina")
        let request = HouseholdJoinRequest(householdId: amina.id, userId: user.id, displayName: user.displayName,
                                           householdName: amina.name, createdAt: .now.addingTimeInterval(-300), status: .pending)
        var repositories = AppRepositories.fake(behavior: .instant)
        repositories.users = FakeUserRepository(users: [user], households: [own, amina], joinRequests: [request])
        return PostSignupOnboardingViewModel(repositories: repositories, userId: user.id, householdId: own.id)
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

#Preview("Ménage trouvé à l'adresse") {
    let model = OnboardingPreview.model()
    PostSignupOnboardingScreen(model: model)
        .task {
            await model.load()
            model.previewJoinChoice(HouseholdAddressEntry(id: "a", householdId: "household-amina", name: "Famille Benali", ownerId: "amina"))
        }
}

#Preview("En attente du propriétaire, sombre") {
    PostSignupOnboardingScreen(model: OnboardingPreview.waitingModel())
        .preferredColorScheme(.dark)
}

#Preview("En attente, AX5") {
    PostSignupOnboardingScreen(model: OnboardingPreview.waitingModel())
        .dynamicTypeSize(.accessibility5)
}
#endif
