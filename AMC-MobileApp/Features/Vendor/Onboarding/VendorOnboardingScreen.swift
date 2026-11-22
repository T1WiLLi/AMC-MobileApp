import PhotosUI
import SwiftUI

/// Onboarding producteur (T-158) : montré par `RootView` quand le portail Vendeurs est ouvert par un compte sans vendeur.
/// Type et nom → production → catégories et quartiers → photos → premier produit → « Ton espace vendeur est prêt ».
struct VendorOnboardingScreen: View {
    @State private var model: VendorOnboardingViewModel
    /// Vendeur créé : ouvre le portail Vendeurs sur ce vendeur.
    private let onFinish: (String) -> Void
    /// « Plus tard » à la première étape : revient au portail Familles.
    private let onCancel: (() -> Void)?

    @State private var pickedItem: PhotosPickerItem?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focus: Field?

    private enum Field { case name, description, search, productName, productOrigin, productPrice }

    init(model: VendorOnboardingViewModel, onFinish: @escaping (String) -> Void = { _ in }, onCancel: (() -> Void)? = nil) {
        _model = State(initialValue: model)
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
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
            .grenierBackground()
            .toolbar { toolbar }
            .navigationBarTitleDisplayMode(.inline)
        }
        .grenierHaptic(.selection, trigger: model.kind)
        .grenierHaptic(.selection, trigger: model.categories)
        .grenierHaptic(.selection, trigger: model.neighborhoods)
        .grenierHaptic(.success, trigger: model.step == .done)
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task { await addPhoto(from: item) }
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
        } else if model.step == .identity, let onCancel {
            ToolbarItem(placement: .topBarLeading) {
                Button("Plus tard", action: onCancel)
                    .accessibilityHint("Revient au portail Familles. Tu pourras devenir vendeur quand tu veux.")
            }
        }
    }

    // MARK: En-tête

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
        case .identity: identityStep
        case .production: productionStep
        case .reach: reachStep
        case .photos: photosStep
        case .product: productStep
        case .done: doneStep
        }
    }

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 150), spacing: 12)]
    }

    // MARK: 1. Type et nom

    private var identityStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Tu es…", systemImage: "person.crop.square.fill")
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(Vendor.Kind.allCases.enumerated()), id: \.element) { index, kind in
                        ChoiceTile(
                            title: VendorKindText.title(for: kind),
                            systemImage: VendorKindText.symbol(for: kind),
                            isSelected: model.kind == kind
                        ) {
                            withAnimation(animation) { model.kind = kind }
                        }
                        .grenierAppear(index: index)
                    }
                }
            }

            card {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Nom de ta ferme ou de ton commerce", systemImage: "signature")
                        .font(.headline)
                        .foregroundStyle(Color.texte)
                    TextField("Nom légal", text: $model.legalName, prompt: Text("Ferme des Voisins"))
                        .font(.title3)
                        .textContentType(.organizationName)
                        .submitLabel(.done)
                        .focused($focus, equals: .name)
                        .padding(12)
                        .background(AppTheme.fond, in: .rect(cornerRadius: 12))
                    Text("Le nom inscrit au registre, ou celui que tes clients connaissent.")
                        .font(.footnote)
                        .foregroundStyle(Color.texteSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: 2. Production

    private var productionStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            card {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Description", systemImage: "text.alignleft")
                        .font(.headline)
                        .foregroundStyle(Color.texte)
                    TextField(
                        "Description de ta production",
                        text: $model.productionDescription,
                        prompt: Text("Légumes bio cultivés à Mirabel depuis 1998, cueillis la veille de la livraison."),
                        axis: .vertical
                    )
                    .lineLimit(5...12)
                    .focused($focus, equals: .description)
                    .padding(12)
                    .background(AppTheme.fond, in: .rect(cornerRadius: 12))
                    HStack(alignment: .firstTextBaseline) {
                        if let error = model.stepError {
                            Label(error, systemImage: "info.circle")
                                .foregroundStyle(Color.texteSecondaire)
                        } else {
                            Label("Parfait, c'est clair.", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color.economie)
                        }
                        Spacer(minLength: 8)
                        Text("\(VendorOnboardingViewModel.Rules.trimmed(model.productionDescription).count)/\(VendorOnboardingViewModel.Rules.descriptionMaxLength)")
                            .monospacedDigit()
                            .foregroundStyle(Color.texteSecondaire)
                            .contentTransition(.numericText())
                            .accessibilityHidden(true)
                    }
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            tip("Parle de tes méthodes (bio, sans pesticides, élevage en plein air), de ta région et de ce qui rend tes produits uniques.")
        }
    }

    // MARK: 3. Catégories et quartiers

    private var reachStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Ce que tu vends", systemImage: "basket.fill")
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
                sectionTitle("Quartiers desservis", systemImage: "mappin.and.ellipse")
                if !model.neighborhoods.isEmpty {
                    FlowChips(items: model.neighborhoods) { neighborhood in
                        withAnimation(animation) { model.toggle(neighborhood) }
                    }
                    .grenierTransition(.banner)
                }
                card {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Chercher un quartier", text: $model.neighborhoodQuery, prompt: Text("Rosemont, Verdun…"))
                            .focused($focus, equals: .search)
                            .submitLabel(.search)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(AppTheme.fond, in: .rect(cornerRadius: 12))
                            .padding(.bottom, 4)
                        let suggestions = model.neighborhoodSuggestions
                        if suggestions.isEmpty {
                            Label("Aucun quartier ne correspond.", systemImage: "magnifyingglass")
                                .font(.subheadline)
                                .foregroundStyle(Color.texteSecondaire)
                                .padding(.vertical, 8)
                        }
                        ForEach(suggestions.prefix(8)) { neighborhood in
                            Button {
                                withAnimation(animation) { model.toggle(neighborhood) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(Color.grenier)
                                        .accessibilityHidden(true)
                                    Text(neighborhood.name)
                                        .font(.body)
                                        .foregroundStyle(Color.texte)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .frame(minHeight: 44)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Ajoute ce quartier")
                        }
                    }
                }
                .animation(animation, value: model.neighborhoodQuery)
            }

            if let error = model.stepError {
                Label(error, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Color.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 4. Photos

    private var photosStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 220 : 140), spacing: 12)], spacing: 12) {
                ForEach(Array(model.photoURLs.enumerated()), id: \.element) { index, url in
                    MediaImage(url: url)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fill)
                        .clipShape(.rect(cornerRadius: 18))
                        .overlay(alignment: .topTrailing) {
                            Button("Retirer la photo", systemImage: "xmark") {
                                withAnimation(animation) { model.removePhoto(url) }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                            .padding(8)
                        }
                        .overlay(alignment: .bottomLeading) {
                            if index == 0 {
                                Label("Couverture", systemImage: "star.fill")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .glassEffect(.regular, in: .capsule)
                                    .padding(8)
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(index == 0 ? "Photo de couverture" : "Photo \(index + 1)")
                        .grenierAppear(index: index)
                }
                if model.canAddPhoto || model.isAddingPhoto {
                    let isAddingPhoto = model.isAddingPhoto
                    PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                        AddVendorPhotoLabel(isLoading: isAddingPhoto)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isAddingPhoto)
                    .accessibilityHint("Ouvre ta photothèque.")
                }
            }
            if let error = model.photoError {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .grenierTransition(.banner)
            }
            tip("La première photo sert de couverture sur ta page. Tu pourras en ajouter d'autres depuis ton profil vendeur.")
        }
    }

    private func addPhoto(from item: PhotosPickerItem) async {
        defer { pickedItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        await model.addPhoto(data: data)
    }

    // MARK: 5. Premier produit

    private var productStep: some View {
        @Bindable var product = model.product
        return VStack(alignment: .leading, spacing: 16) {
            card {
                VStack(alignment: .leading, spacing: 12) {
                    productField("Nom du produit", text: $product.name, prompt: "Carottes nantaises", field: .productName,
                                 systemImage: "tag.fill")
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Catégorie", systemImage: ProductIcon.symbol(for: product.category))
                            .font(.headline)
                            .foregroundStyle(Color.texte)
                            .contentTransition(.symbolEffect(.replace))
                        Picker("Catégorie", selection: $product.category) {
                            ForEach(model.orderedCategories.isEmpty ? Product.Category.allCases : model.orderedCategories,
                                    id: \.self) { category in
                                Text(category.title).tag(category)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.grenier)
                        .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Unité de vente", systemImage: "scalemass.fill")
                            .font(.headline)
                            .foregroundStyle(Color.texte)
                        ProductUnitPicker(selection: $product.unit)
                    }
                    productField("Provenance", text: $product.origin, prompt: "Mirabel, QC", field: .productOrigin,
                                 systemImage: "location.fill")
                    productField("Prix en épicerie", text: $product.referencePriceText, prompt: "8,99 $",
                                 field: .productPrice, systemImage: "dollarsign.circle.fill", keyboard: .decimalPad)
                    Text("Le prix d'une unité en épicerie : on s'en sert pour montrer l'économie des familles.")
                        .font(.footnote)
                        .foregroundStyle(Color.texteSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if model.hasProductDraft, let error = model.stepError {
                Label(error, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Color.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                    .grenierTransition(.banner)
            }
            if let error = model.saveError {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .grenierTransition(.banner)
            }
        }
        .onAppear {
            if let first = model.orderedCategories.first, !model.orderedCategories.contains(model.product.category) {
                model.product.category = first
            }
        }
    }

    private func productField(
        _ title: LocalizedStringKey,
        text: Binding<String>,
        prompt: LocalizedStringKey,
        field: Field,
        systemImage: String,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Color.texte)
            TextField(title, text: text, prompt: Text(prompt))
                .keyboardType(keyboard)
                .focused($focus, equals: field)
                .padding(12)
                .background(AppTheme.fond, in: .rect(cornerRadius: 12))
        }
    }

    // MARK: 6. Fini

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VerificationPendingBadge()
                Spacer(minLength: 0)
            }
            .grenierAppear(index: 0)
            SummaryRow(title: "Vendeur", value: model.identitySummary,
                       systemImage: VendorKindText.symbol(for: model.kind))
                .grenierAppear(index: 1)
            SummaryRow(title: "Tu vends", value: model.categoriesSummary, systemImage: "basket.fill")
                .grenierAppear(index: 2)
            SummaryRow(title: "Quartiers", value: model.zonesSummary, systemImage: "mappin.and.ellipse")
                .grenierAppear(index: 3)
            SummaryRow(title: "Photos", value: model.photosSummary, systemImage: "photo.fill")
                .grenierAppear(index: 4)
            SummaryRow(title: "Premier produit", value: model.productSummary, systemImage: "shippingbox.fill")
                .grenierAppear(index: 5)
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
        case .identity, .production, .reach: String(localized: "Continuer")
        case .photos: model.photoURLs.isEmpty ? String(localized: "Continuer sans photo") : String(localized: "Continuer")
        case .product:
            if model.isSaving { String(localized: "Création…") }
            else { model.hasProductDraft ? String(localized: "Créer mon espace vendeur") : String(localized: "Créer sans produit") }
        case .done: String(localized: "Ouvrir mon tableau de bord")
        }
    }

    private var primaryHint: String {
        if let error = model.stepError { return error }
        return switch model.step {
        case .product: String(localized: "Crée ton profil vendeur et ouvre le portail Vendeurs")
        case .done: String(localized: "Ouvre le portail Vendeurs")
        default: String(localized: "Passe à l'étape suivante")
        }
    }

    private func primaryAction() {
        focus = nil
        if model.step == .done {
            onFinish(model.createdVendor?.id ?? model.vendorId)
            return
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

    private func tip(_ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(Color.solidarite)
        }
        .font(.footnote)
        .foregroundStyle(Color.texteSecondaire)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: .rect(cornerRadius: 20))
    }
}

// MARK: - Ajout de photo

/// Tuile « Ajouter une photo » (vue à part : le libellé de PhotosPicker est un contexte non isolé).
private struct AddVendorPhotoLabel: View {
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 8) {
            if isLoading {
                ProgressView()
            } else {
                Image(systemName: "photo.badge.plus")
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                Text("Ajouter une photo")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(Color.grenier)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 140)
        .aspectRatio(1, contentMode: .fit)
        .background(Color.grenier.opacity(0.12), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.grenier.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }
        .contentShape(.rect(cornerRadius: 18))
    }
}

// MARK: - Quartiers choisis

/// Puces des quartiers choisis ; toucher une puce la retire.
private struct FlowChips: View {
    let items: [MontrealNeighborhood]
    let onRemove: (MontrealNeighborhood) -> Void

    var body: some View {
        ChipFlowLayout(spacing: 8) {
            ForEach(items) { neighborhood in
                Button {
                    onRemove(neighborhood)
                } label: {
                    Label(neighborhood.name, systemImage: "xmark.circle.fill")
                        .labelStyle(ChipTrailingIconLabelStyle())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.onAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .background(Color.grenier, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(neighborhood.name)
                .accessibilityHint("Retire ce quartier")
                .accessibilityAddTraits(.isSelected)
            }
        }
    }
}

private struct ChipTrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}

/// Disposition en lignes qui passent à la ligne (puces).
private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let itemWidth = min(size.width, width)
            let needed = current.indices.isEmpty ? itemWidth : current.width + spacing + itemWidth
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row(indices: [index], width: itemWidth, height: size.height)
            } else {
                current.indices.append(index)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
private enum VendorOnboardingPreview {
    static func model() -> VendorOnboardingViewModel {
        let user = AppUser(
            id: "user-nouveau", displayName: "Julien Tremblay", photoURL: nil, language: .french, roles: [.family],
            neighborhood: "Rosemont", dietaryPreferences: [], seniorMode: false, householdId: nil, vendorId: nil
        )
        var repositories = AppRepositories.fake(behavior: .instant)
        repositories.users = FakeUserRepository(users: [user], households: [])
        return VendorOnboardingViewModel(repositories: repositories, userId: user.id)
    }

    static func filled() -> VendorOnboardingViewModel {
        let model = model()
        model.kind = .farm
        model.legalName = "Ferme des Voisins"
        model.productionDescription = "Légumes bio cultivés à Mirabel, cueillis la veille de la livraison."
        model.toggle(.produce)
        model.toggle(.eggs)
        if let first = MontrealNeighborhood.all.first { model.toggle(first) }
        return model
    }
}

#Preview("Type et nom") {
    VendorOnboardingScreen(model: VendorOnboardingPreview.model(), onCancel: {})
}

#Preview("Type et nom, sombre") {
    VendorOnboardingScreen(model: VendorOnboardingPreview.model(), onCancel: {})
        .preferredColorScheme(.dark)
}

#Preview("Rempli") {
    VendorOnboardingScreen(model: VendorOnboardingPreview.filled())
}

#Preview("AX5") {
    VendorOnboardingScreen(model: VendorOnboardingPreview.model(), onCancel: {})
        .dynamicTypeSize(.accessibility5)
}
#endif
