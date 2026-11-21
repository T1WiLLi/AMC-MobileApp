// ProductEditorScreen.swift
// « Nouveau produit » / « Modifier le produit » du portail Vendeur (T-089, S-04) : photo, nom, catégorie,
// unité, provenance, prix de base, étiquettes ; retrait avec confirmation.
// Logique et validation dans `ProductEditorViewModel` ; la photo est redimensionnée ici (`ProductPhoto.jpegData`)
// puis téléversée par le ViewModel à l'enregistrement.

import PhotosUI
import SwiftUI

struct ProductEditorScreen: View {
    private enum Field: Hashable { case name, unit, origin, price }

    @State private var model: ProductEditorViewModel
    private let onSaved: (Product) -> Void
    private let onDeleted: (String) -> Void

    @State private var pickerItem: PhotosPickerItem?
    /// Aperçu local de la photo choisie (pas encore téléversée).
    @State private var pendingImage: UIImage?
    @State private var isProcessingPhoto = false
    @State private var photoError: String?
    /// Les messages de validation n'apparaissent qu'après un premier essai d'enregistrement.
    @State private var showsValidation = false
    @State private var confirmsDelete = false
    @State private var warningTrigger = 0
    @State private var errorTrigger = 0
    @FocusState private var focusedField: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var photoHeight: CGFloat = 200

    /// Unités proposées dans le menu à côté du champ.
    private static let unitSuggestions = ["kg", "sac de 10 kg", "sac de 20 kg", "douzaine", "litre", "caisse de 12", "pot de 500 g"]

    init(
        repositories: AppRepositories,
        vendorId: String,
        productId: String? = nil,
        photoUploader: any ProductPhotoUploader = FakeProductPhotoUploader(),
        onSaved: @escaping (Product) -> Void = { _ in },
        onDeleted: @escaping (String) -> Void = { _ in }
    ) {
        _model = State(initialValue: ProductEditorViewModel(
            repositories: repositories, vendorId: vendorId, productId: productId, photoUploader: photoUploader
        ))
        self.onSaved = onSaved
        self.onDeleted = onDeleted
    }

    var body: some View {
        StateView(state: model.loadState, retry: { await model.load() }) { _ in
            form
        }
        .navigationTitle(model.isEditing ? String(localized: "Modifier le produit") : String(localized: "Nouveau produit"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if model.loadState.value != nil { saveButton }
        }
        .task {
            if case .idle = model.loadState { await model.load() }
        }
        .onChange(of: pickerItem) { _, item in
            Task { await loadPhoto(item) }
        }
        .grenierHaptic(.warning, trigger: warningTrigger)
        .grenierHaptic(.error, trigger: errorTrigger)
        .confirmationDialog(
            String(localized: "Retirer « \(model.name) » du catalogue ?"),
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button("Retirer le produit", role: .destructive) {
                Task { await delete() }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les familles ne le verront plus et tu ne pourras plus l'utiliser pour un lot. Cette action est définitive.")
        }
    }

    // MARK: Formulaire

    private var form: some View {
        Form {
            photoSection
            productSection
            priceSection
            tagsSection
            if let message = feedbackMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.bubble.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.orange)
                        .font(.subheadline.weight(.medium))
                        .symbolEffect(.wiggle, options: .nonRepeating, value: reduceMotion ? 0 : warningTrigger + errorTrigger)
                }
                .transition(.opacity)
            }
            if model.isEditing { deleteSection }
        }
        .scrollContentBackground(.hidden)
        .grenierBackground()
        .scrollDismissesKeyboard(.interactively)
        .grenierAnimation(.smooth, value: feedbackMessage)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK", systemImage: "keyboard.chevron.compact.down") { focusedField = nil }
            }
        }
    }

    // MARK: Photo

    private var photoSection: some View {
        Section {
            photoPreview
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))

            // Le libellé de PhotosPicker est une closure Sendable : on calcule le texte avant.
            let pickerTitle = model.hasPhoto ? String(localized: "Changer la photo") : String(localized: "Choisir une photo")
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Label(pickerTitle, systemImage: "photo.badge.plus")
                    .symbolRenderingMode(.hierarchical)
            }
            .disabled(isProcessingPhoto || model.isSaving)

            if model.hasPhoto {
                Button("Retirer la photo", systemImage: "photo.badge.minus", role: .destructive) {
                    withGrenierAnimation(.smooth, reduceMotion: reduceMotion) {
                        model.removePhoto()
                        pendingImage = nil
                        pickerItem = nil
                        photoError = nil
                    }
                }
                .disabled(model.isSaving)
            }
        } header: {
            Label("Photo", systemImage: "camera.fill")
        } footer: {
            if let photoError {
                Label(photoError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else {
                Text("Une belle photo aide les familles à choisir. Elle est redimensionnée automatiquement.")
            }
        }
    }

    private var photoPreview: some View {
        ZStack {
            if let pendingImage {
                Image(uiImage: pendingImage)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if let url = model.photoURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        photoPlaceholder
                    }
                }
            } else {
                photoPlaceholder
            }
            if isProcessingPhoto {
                ProgressView()
                    .controlSize(.large)
                    .padding(16)
                    .glassEffect(.regular, in: .circle)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: photoHeight)
        .clipShape(.rect(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.hasPhoto ? String(localized: "Photo du produit") : String(localized: "Aucune photo, icône de la catégorie \(model.category.title)"))
    }

    private var photoPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.grenier.opacity(0.18), Color.grenier.opacity(0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(spacing: 8) {
                Image(systemName: ProductIcon.symbol(for: model.category))
                    .font(.system(.largeTitle))
                    .imageScale(.large)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
                    .contentTransition(.symbolEffect(.replace))
                Text("Aucune photo")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            }
        }
    }

    // MARK: Produit

    private var productSection: some View {
        Section {
            fieldRow("textformat") {
                TextField("Nom du produit", text: $model.name, prompt: Text("Ex. Farine de blé intégrale"))
                    .focused($focusedField, equals: .name)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .unit }
            }

            Picker(selection: $model.category) {
                ForEach(model.categories, id: \.self) { category in
                    Label(category.title, systemImage: ProductIcon.symbol(for: category))
                        .tag(category)
                }
            } label: {
                Label("Catégorie", systemImage: ProductIcon.symbol(for: model.category))
                    .contentTransition(.symbolEffect(.replace))
            }
            .pickerStyle(.navigationLink)
            .symbolRenderingMode(.hierarchical)
            .grenierHaptic(.selection, trigger: model.category)

            fieldRow("scalemass.fill") {
                TextField("Unité de vente", text: $model.unit, prompt: Text("Ex. sac de 10 kg"))
                    .focused($focusedField, equals: .unit)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .origin }
                Menu {
                    ForEach(Self.unitSuggestions, id: \.self) { unit in
                        Button(unit) { model.unit = unit }
                    }
                } label: {
                    Image(systemName: "list.bullet.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.grenier)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Unités suggérées")
            }

            fieldRow("mappin.and.ellipse") {
                TextField("Provenance", text: $model.origin, prompt: Text("Ex. Mirabel, QC"))
                    .focused($focusedField, equals: .origin)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .price }
            }
        } header: {
            Label("Produit", systemImage: "tag.fill")
        }
    }

    // MARK: Prix

    private var priceSection: some View {
        Section {
            fieldRow("cart.fill") {
                TextField("Prix en épicerie", text: $model.referencePriceText, prompt: Text("0,00"))
                    .focused($focusedField, equals: .price)
                    .keyboardType(.decimalPad)
                    .monospacedDigit()
                Text("$")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.texteSecondaire)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Prix en épicerie, en dollars")
        } header: {
            Label("Prix de base", systemImage: "dollarsign.circle.fill")
        } footer: {
            if let cents = model.referenceGroceryPriceCents, cents > 0 {
                Text("Prix d'épicerie pour une unité : \(Money.format(cents)). Les familles y comparent le prix de tes lots.")
                    .contentTransition(.numericText())
            } else {
                Text("Prix d'épicerie pour une unité, comme « 3,49 ». Il sert à montrer l'économie aux familles.")
            }
        }
    }

    // MARK: Étiquettes

    private var tagsSection: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(DietaryTag.allCases, id: \.self) { tag in
                        Toggle(isOn: Binding(
                            get: { model.isTagged(tag) },
                            set: { _ in model.toggleTag(tag) }
                        )) {
                            Label(tag.editorTitle, systemImage: tag.editorSymbol)
                                .font(.subheadline.weight(.medium))
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(model.isTagged(tag) ? Color.grenier : Color.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            .grenierHaptic(.selection, trigger: model.tags)
        } header: {
            Label("Étiquettes", systemImage: "checkmark.seal.fill")
        } footer: {
            Text("Les familles peuvent filtrer les lots selon ces étiquettes.")
        }
    }

    // MARK: Retrait

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                confirmsDelete = true
            } label: {
                HStack {
                    Label("Retirer du catalogue", systemImage: "trash")
                    Spacer()
                    if model.isDeleting { ProgressView() }
                }
            }
            .disabled(model.isDeleting || model.isSaving)
        } footer: {
            Text("Impossible tant qu'un lot ouvert ou en pause utilise ce produit.")
        }
    }

    // MARK: Enregistrer

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            HStack(spacing: 8) {
                if model.isSaving {
                    ProgressView().tint(.onAccent)
                } else {
                    Image(systemName: model.isEditing ? "checkmark.circle.fill" : "plus.circle.fill")
                }
                Text(model.isSaving ? String(localized: "Enregistrement…") : (model.isEditing ? String(localized: "Enregistrer") : String(localized: "Ajouter au catalogue")))
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.glassProminent)
        .tint(.grenier)
        .controlSize(.large)
        .disabled(model.isSaving || model.isDeleting || isProcessingPhoto)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityHint(model.isEditing ? String(localized: "Enregistre tes changements.") : String(localized: "Ajoute le produit à ton catalogue."))
    }

    // MARK: Actions

    /// Erreur de validation (après un premier essai) ou échec d'enregistrement / de retrait.
    private var feedbackMessage: String? {
        if let error = model.deleteState.error { return error.message }
        if let error = model.saveState.error { return error.message }
        if showsValidation, let error = model.validationError { return error.message }
        return nil
    }

    private func save() async {
        focusedField = nil
        guard model.validationError == nil else {
            withGrenierAnimation(.smooth, reduceMotion: reduceMotion) { showsValidation = true }
            warningTrigger += 1
            return
        }
        if let product = await model.save() {
            onSaved(product)
        } else {
            errorTrigger += 1
        }
    }

    private func delete() async {
        guard case .edit(let productId) = model.mode else { return }
        if await model.delete() {
            onDeleted(productId)
        } else {
            errorTrigger += 1
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isProcessingPhoto = true
        defer { isProcessingPhoto = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                photoError = String(localized: "Cette photo n'est pas disponible. Choisis-en une autre.")
                return
            }
            let jpeg = await Task.detached(priority: .userInitiated) { ProductPhoto.jpegData(from: data) }.value
            guard let jpeg, let image = UIImage(data: jpeg) else {
                photoError = String(localized: "Ce fichier n'est pas une image lisible. Choisis-en une autre.")
                warningTrigger += 1
                return
            }
            withGrenierAnimation(.smooth, reduceMotion: reduceMotion) {
                model.setPhoto(jpeg)
                pendingImage = image
                photoError = nil
            }
        } catch {
            photoError = String(localized: "Impossible d'ouvrir cette photo. Réessaie ou choisis-en une autre.")
            errorTrigger += 1
        }
    }

    /// Ligne de formulaire avec une icône de tête alignée.
    private func fieldRow<Content: View>(_ symbol: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .frame(width: 24)
                .accessibilityHidden(true)
            content()
        }
    }
}

// MARK: - Étiquettes (libellés de l'éditeur)

private extension DietaryTag {
    var editorTitle: String {
        switch self {
        case .organic: String(localized: "Biologique")
        case .halal: String(localized: "Halal")
        case .kosher: String(localized: "Casher")
        case .vegetarian: String(localized: "Végétarien")
        case .vegan: String(localized: "Végane")
        case .glutenFree: String(localized: "Sans gluten")
        case .local: String(localized: "Local")
        }
    }

    var editorSymbol: String {
        switch self {
        case .organic: "leaf.fill"
        case .halal: "moon.stars.fill"
        case .kosher: "star.fill"
        case .vegetarian: "carrot.fill"
        case .vegan: "leaf.circle.fill"
        case .glutenFree: "allergens.fill"
        case .local: "mappin.circle.fill"
        }
    }
}

#if DEBUG
#Preview("Nouveau produit") {
    NavigationStack {
        ProductEditorScreen(repositories: .fake(behavior: .instant), vendorId: FakeData.ID.fermeRive)
    }
}

#Preview("Modifier, sombre") {
    NavigationStack {
        ProductEditorScreen(
            repositories: .fake(behavior: .instant), vendorId: FakeData.ID.fermeRive, productId: FakeData.ID.potatoes
        )
    }
    .preferredColorScheme(.dark)
}
#endif
