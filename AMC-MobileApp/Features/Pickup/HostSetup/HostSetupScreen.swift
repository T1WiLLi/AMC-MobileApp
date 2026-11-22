import PhotosUI
import SwiftUI

/// RQ-062 (T-077) : devenir hôte (ou modifier son point) — photo, nom, adresse, capacité, accessibilité.
/// Poussé dans le `NavigationStack` de la Cueillette.
struct HostSetupScreen: View {
    @State private var viewModel: HostSetupViewModel

    init(viewModel: HostSetupViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        StateView(state: viewModel.loadState, retry: { await viewModel.load() }) { _ in
            HostSetupForm(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
        .navigationTitle(viewModel.isEditing ? String(localized: "Mon point de cueillette") : String(localized: "Devenir hôte"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .task { if viewModel.loadState.value == nil { await viewModel.load() } }
    }
}

private struct HostSetupForm: View {
    @Bindable var viewModel: HostSetupViewModel
    @State private var photoItem: PhotosPickerItem?
    @State private var showsValidation = false
    @FocusState private var focusedField: Field?
    @FocusState private var addressFocused: Bool

    private enum Field { case name }

    var body: some View {
        Form {
            Section {
                HostIntroRow(isEditing: viewModel.isEditing)
            }
            .listRowBackground(Color.surface)

            Section {
                HostPhotoRow(viewModel: viewModel, photoItem: $photoItem)
            } header: {
                Label("Photo de l'entrée", systemImage: "camera.fill")
            } footer: {
                Text("Aide les voisins à reconnaître la porte. Évite les visages et le numéro d'appartement.")
            }
            .listRowBackground(Color.surface)

            Section {
                TextField("Nom du point", text: $viewModel.name, prompt: Text("Chez Amina, rue Jarry"))
                    .textContentType(.organizationName)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { addressFocused = true }
                AddressField("Adresse", text: $viewModel.address, model: viewModel.addressCheck,
                             prompt: "7420 rue Ogilvy, Montréal", isFocused: $addressFocused)
            } header: {
                Label("Lieu", systemImage: "mappin.and.ellipse")
            } footer: {
                Text("L'adresse exacte n'est montrée qu'aux membres des groupes qui choisissent ton point.")
            }
            .listRowBackground(Color.surface)

            Section {
                HostCapacityRow(capacity: $viewModel.capacity)
            } header: {
                Label("Capacité", systemImage: "shippingbox.fill")
            } footer: {
                Text("Nombre de parts que tu peux garder chez toi en même temps (sacs, caisses).")
            }
            .listRowBackground(Color.surface)

            Section {
                ForEach(PickupPoint.Accessibility.allCases, id: \.self) { option in
                    AccessibilityToggleRow(
                        option: option,
                        isOn: Binding(
                            get: { viewModel.accessibility.contains(option) },
                            set: { _ in viewModel.toggle(option) }
                        )
                    )
                }
            } header: {
                Label("Accessibilité", systemImage: "figure.roll")
            }
            .listRowBackground(Color.surface)

            if showsValidation, let error = viewModel.validationError ?? viewModel.saveError {
                Section {
                    Label(error.message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.grenier)
                        .font(.subheadline)
                }
                .listRowBackground(Color.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { saveBar }
        .onChange(of: photoItem) { _, item in
            Task { await loadPhoto(item) }
        }
        .grenierHaptic(.success, trigger: viewModel.savedPoint)
        .grenierHaptic(.warning, trigger: showsValidation) { _, new in new }
    }

    private var saveBar: some View {
        VStack(spacing: 8) {
            if let saved = viewModel.savedPoint, viewModel.saveError == nil {
                Label("\(saved.name) est enregistré", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.economie)
                    .symbolEffect(.bounce, value: viewModel.savedPoint)
                    .grenierTransition(.banner)
            }
            Button {
                focusedField = nil
                addressFocused = false
                guard viewModel.validationError == nil else {
                    showsValidation = true
                    return
                }
                Task {
                    showsValidation = await viewModel.save() == nil
                }
            } label: {
                Label(viewModel.isEditing ? String(localized: "Enregistrer") : String(localized: "Devenir hôte"),
                      systemImage: viewModel.isEditing ? "checkmark" : "house.and.flag.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(alignment: .trailing) {
                        if viewModel.isSaving { ProgressView().tint(.onAccent) }
                    }
            }
            .buttonStyle(.glassProminent)
            .tint(.grenier)
            .disabled(viewModel.isSaving || viewModel.addressCheck.blocksSaving(viewModel.address))
            .accessibilityHint(viewModel.validationError?.message ?? "")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .grenierAnimation(.smooth, value: viewModel.savedPoint)
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        viewModel.photoData = data
    }
}

/// En-tête : ce que veut dire être hôte, en trois secondes.
private struct HostIntroRow: View {
    let isEditing: Bool
    @ScaledMetric(relativeTo: .headline) private var iconSize: CGFloat = 52

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "house.and.flag.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .frame(width: iconSize, height: iconSize)
                .background(Color.grenier.opacity(0.12), in: .rect(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(isEditing ? String(localized: "Ton point de cueillette") : String(localized: "Accueille les livraisons du quartier"))
                    .font(.headline)
                    .foregroundStyle(.texte)
                Text("Le vendeur dépose les lots chez toi, les voisins passent les chercher pendant les créneaux.")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct HostPhotoRow: View {
    let viewModel: HostSetupViewModel
    @Binding var photoItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            preview
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipShape(.rect(cornerRadius: 16))
                .accessibilityLabel(hasPhoto ? String(localized: "Photo du point de cueillette") : String(localized: "Aucune photo"))
            let pickerTitle = hasPhoto ? String(localized: "Changer") : String(localized: "Choisir une photo")
            HStack(spacing: 12) {
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Label(pickerTitle, systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)
                if hasPhoto {
                    Button(role: .destructive) {
                        photoItem = nil
                        viewModel.removePhoto()
                    } label: {
                        Label("Retirer", systemImage: "trash")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var hasPhoto: Bool { viewModel.photoData != nil || viewModel.photoURL != nil }

    @ViewBuilder private var preview: some View {
        if let data = viewModel.photoData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else if let url = viewModel.photoURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                photoPlaceholder.redacted(reason: .placeholder)
            }
        } else {
            photoPlaceholder
        }
    }

    private var photoPlaceholder: some View {
        ZStack {
            Color.piste
            VStack(spacing: 8) {
                Image(systemName: "door.left.hand.open")
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
                Text("Ta porte, ton hall ou ton balcon")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            }
        }
    }
}

private struct HostCapacityRow: View {
    @Binding var capacity: Int

    var body: some View {
        Stepper(value: $capacity, in: HostSetupViewModel.capacityRange, step: 1) {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(capacity) parts")
                        .priceStyle(.title3.bold())
                        .contentTransition(.numericText(value: Double(capacity)))
                        .grenierAnimation(.snappy, value: capacity)
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.texteSecondaire)
                }
            }
        }
        .accessibilityLabel("Capacité")
        .accessibilityValue("\(capacity) parts")
        .grenierHaptic(.selection, trigger: capacity)
    }

    private var hint: String {
        switch capacity {
        case ..<10: String(localized: "Un coin d'entrée suffit")
        case ..<30: String(localized: "Un placard ou un bout de garage")
        default: String(localized: "Un local, une salle ou un sous-sol")
        }
    }
}

private struct AccessibilityToggleRow: View {
    let option: PickupPoint.Accessibility
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).foregroundStyle(.texte)
                    Text(option.detail).font(.caption).foregroundStyle(.texteSecondaire)
                }
            } icon: {
                Image(systemName: option.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isOn ? Color.grenier : Color.secondary)
                    .symbolEffect(.bounce, value: isOn)
            }
        }
        .tint(.grenier)
        .frame(minHeight: 44)
        .grenierHaptic(.selection, trigger: isOn)
    }
}

#Preview("Nouvel hôte") {
    NavigationStack {
        HostSetupScreen(viewModel: HostSetupViewModel(repositories: .fake(behavior: .instant), userId: "user-nouveau"))
    }
}

#Preview("Modifier (sombre)") {
    NavigationStack {
        HostSetupScreen(viewModel: HostSetupViewModel(repositories: .fake(), userId: FakeData.ID.amina))
    }
    .preferredColorScheme(.dark)
}

#Preview("AX5") {
    NavigationStack {
        HostSetupScreen(viewModel: HostSetupViewModel(repositories: .fake(behavior: .instant), userId: FakeData.ID.amina))
    }
    .dynamicTypeSize(.accessibility5)
}
