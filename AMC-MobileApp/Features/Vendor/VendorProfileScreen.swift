import MapKit
import PhotosUI
import SwiftUI

/// « Ma vitrine » (T-076, RQ-016, T-157) : photos, description, produits mis en avant et zones desservies,
/// tels que les familles les voient sur la page producteur. Raison sociale et type en lecture seule.
/// Présenté en feuille depuis le Tableau de bord vendeur.
struct VendorProfileScreen: View {
    @State private var viewModel: VendorProfileViewModel
    @State private var pickedItem: PhotosPickerItem?
    @State private var zoneDraft = ""
    @State private var fieldError: AppError?
    @State private var savedCount = 0
    @State private var rejectedCount = 0
    @State private var confirmsDiscard = false
    @State private var showsZoneMap = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        repositories: AppRepositories,
        vendorId: String,
        photoStore: (any VendorPhotoStoring)? = nil
    ) {
        _viewModel = State(initialValue: VendorProfileViewModel(
            repositories: repositories, vendorId: vendorId, photoStore: photoStore
        ))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Ma vitrine")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .task { if viewModel.state.value == nil { await viewModel.load() } }
                .grenierHaptic(.success, trigger: savedCount)
                .grenierHaptic(.warning, trigger: rejectedCount)
                .interactiveDismissDisabled(viewModel.hasChanges)
                .confirmationDialog("Quitter sans enregistrer ?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                    Button("Abandonner les modifications", role: .destructive) {
                        viewModel.discardChanges()
                        dismiss()
                    }
                    Button("Continuer l'édition", role: .cancel) {}
                }
        }
    }

    // MARK: - États

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            form(vendor: .profilePlaceholder)
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Chargement du profil")
        case .failed, .empty:
            StateView(state: viewModel.state, retry: { await viewModel.load() }) { _ in EmptyView() }
        case .loaded(let vendor):
            form(vendor: vendor)
        }
    }

    private func form(vendor: Vendor) -> some View {
        Form {
            Section {
                VendorIdentityHeader(vendor: vendor, coverURL: viewModel.photoURLs.first)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            photosSection
            descriptionSection
            featuredSection
            zonesSection

            if let error = viewModel.saveState.error {
                Section {
                    Label(error.message, systemImage: error.systemImage)
                        .foregroundStyle(.red)
                        .symbolRenderingMode(.hierarchical)
                }
                .grenierTransition(.banner)
            }
        }
        .scrollContentBackground(.hidden)
        .grenierBackground()
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Photos

    private var photosSection: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(viewModel.photoURLs.enumerated()), id: \.element) { index, url in
                        PhotoThumbnail(url: url, isCover: index == 0)
                            .contextMenu {
                                if index > 0 {
                                    Button("Mettre en couverture", systemImage: "star") {
                                        withGrenierAnimation(.snappy, reduceMotion: reduceMotion) { viewModel.makeCover(url) }
                                    }
                                }
                                Button("Retirer", systemImage: "trash", role: .destructive) {
                                    withGrenierAnimation(.smooth, reduceMotion: reduceMotion) { viewModel.removePhoto(url) }
                                }
                            }
                            .accessibilityAction(named: "Retirer") { viewModel.removePhoto(url) }
                            .accessibilityAction(named: "Mettre en couverture") { viewModel.makeCover(url) }
                    }
                    if viewModel.canAddPhoto {
                        // Valeur lue ici : le libellé de `PhotosPicker` est une closure `@Sendable`.
                        let isAddingPhoto = viewModel.isAddingPhoto
                        PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                            AddPhotoTile(isLoading: isAddingPhoto)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Ajouter une photo")
                        .accessibilityHint("Ouvre ta photothèque.")
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                Task { await addPhoto(from: item) }
            }
        } header: {
            sectionHeader("Photos", systemImage: "photo.on.rectangle.angled",
                          count: viewModel.photoURLs.count, max: VendorProfileViewModel.maxPhotos)
        }
    }

    /// Titre de section avec son compteur à droite (« 3 / 6 »), à la place des longs pieds de section.
    private func sectionHeader(_ title: LocalizedStringKey, systemImage: String, count: Int, max: Int) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text("\(count) / \(max)")
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(count >= max ? Color.grenier : .secondary)
                .accessibilityLabel("\(count) sur \(max)")
        }
        .symbolRenderingMode(.hierarchical)
    }

    private func addPhoto(from item: PhotosPickerItem) async {
        defer { pickedItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                reject(.invalidInput(String(localized: "Impossible de lire cette image.")))
                return
            }
            if let error = await viewModel.addPhoto(data: data) { reject(error) }
        } catch {
            reject(AppError(error))
        }
    }

    // MARK: - Description

    private var descriptionSection: some View {
        Section {
            TextField(
                String(localized: "Ce que tu cultives ou vends, d'où ça vient, ce qui te rend fier…"),
                text: $viewModel.description,
                axis: .vertical
            )
            .lineLimit(4...12)
            .accessibilityLabel("Description")
        } header: {
            Label("Description", systemImage: "text.alignleft")
        } footer: {
            let count = viewModel.description.trimmingCharacters(in: .whitespacesAndNewlines).count
            HStack {
                Spacer()
                Text("\(count) / \(VendorProfileViewModel.descriptionMaxLength)")
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(count < VendorProfileViewModel.descriptionMinLength
                                     || count > VendorProfileViewModel.descriptionMaxLength ? Color.red : .secondary)
                    .accessibilityLabel("\(count) caractères sur \(VendorProfileViewModel.descriptionMaxLength)")
            }
        }
    }

    // MARK: - Produits mis en avant (T-157)

    private var featuredSection: some View {
        Section {
            if viewModel.products.isEmpty {
                Label("Aucun produit pour l'instant", systemImage: "basket")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.products) { product in
                    let featured = viewModel.isFeatured(product.id)
                    Button {
                        withGrenierAnimation(.snappy, reduceMotion: reduceMotion) {
                            if let error = viewModel.toggleFeatured(product.id) { reject(error) }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: ProductIcon.symbol(for: product.category))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.grenier)
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.name).foregroundStyle(Color.texte)
                                Text(product.displayUnit).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: featured ? "heart.fill" : "heart")
                                .font(.title3)
                                .foregroundStyle(featured ? Color.grenier : Color.secondary)
                                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(product.name)
                    .accessibilityValue(featured ? String(localized: "mis en avant") : String(localized: "pas mis en avant"))
                    .accessibilityAddTraits(featured ? [.isButton, .isSelected] : .isButton)
                }
            }
        } header: {
            sectionHeader("Coups de cœur", systemImage: "heart.text.square",
                          count: viewModel.featuredProductIds.count, max: VendorProfileViewModel.maxFeatured)
        }
        .sensoryFeedback(.selection, trigger: viewModel.featuredProductIds)
    }

    // MARK: - Zones

    private var zonesSection: some View {
        Section {
            if viewModel.servedZones.isEmpty {
                Label("Aucune zone", systemImage: "mappin.slash")
                    .foregroundStyle(.secondary)
            } else {
                ChipFlow {
                    ForEach(viewModel.servedZones, id: \.self) { zone in
                        ZoneChip(title: viewModel.label(forZone: zone), style: .selected) {
                            withGrenierAnimation(.snappy, reduceMotion: reduceMotion) { viewModel.removeZone(zone) }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if !viewModel.zoneSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Suggestions")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ChipFlow {
                        ForEach(viewModel.zoneSuggestions) { option in
                            ZoneChip(title: option.label, style: .suggestion) {
                                addZone(option.id)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // QA T-094 n° 17b : le vendeur choisit un quartier par son nom ou sur la carte ;
            // le geohash est calculé et enregistré sans jamais être montré.
            Label {
                TextField("Chercher un quartier", text: $zoneDraft)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit {
                        if let first = neighborhoodMatches.first { addNeighborhood(first) }
                    }
            } icon: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
            }

            if !zoneDraft.trimmingCharacters(in: .whitespaces).isEmpty {
                if neighborhoodMatches.isEmpty {
                    Label("Aucun résultat", systemImage: "map")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ChipFlow {
                        ForEach(neighborhoodMatches) { neighborhood in
                            ZoneChip(title: neighborhood.name, style: .suggestion) {
                                addNeighborhood(neighborhood)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Button {
                showsZoneMap = true
            } label: {
                Label("Choisir sur la carte", systemImage: "map.fill")
                    .symbolRenderingMode(.hierarchical)
            }
            .tint(.grenier)
            .sheet(isPresented: $showsZoneMap) {
                ZoneMapPicker(
                    label: { latitude, longitude in
                        let zone = Geohash.encode(
                            latitude: latitude, longitude: longitude,
                            precision: VendorProfileViewModel.neighborhoodZonePrecision
                        )
                        return viewModel.label(forZone: zone)
                    },
                    onPick: { latitude, longitude in
                        if let error = viewModel.addZone(latitude: latitude, longitude: longitude) {
                            reject(error)
                        } else {
                            fieldError = nil
                        }
                    }
                )
            }

            if let fieldError {
                Label(fieldError.message, systemImage: fieldError.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        } header: {
            sectionHeader("Zones desservies", systemImage: "map.fill",
                          count: viewModel.servedZones.count, max: VendorProfileViewModel.maxZones)
        }
    }

    /// Quartiers qui correspondent à la recherche (6 au plus).
    private var neighborhoodMatches: [MontrealNeighborhood] {
        Array(viewModel.neighborhoodMatches(zoneDraft).prefix(6))
    }

    private func addNeighborhood(_ neighborhood: MontrealNeighborhood) {
        if let error = viewModel.addNeighborhood(neighborhood) {
            reject(error)
        } else {
            fieldError = nil
            zoneDraft = ""
        }
    }

    private func addZone(_ zone: String) {
        if let error = viewModel.addZone(zone) {
            reject(error)
        } else {
            fieldError = nil
            zoneDraft = ""
        }
    }

    private func reject(_ error: AppError) {
        withGrenierAnimation(.smooth, reduceMotion: reduceMotion) { fieldError = error }
        rejectedCount += 1
    }

    // MARK: - Barre

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Fermer", systemImage: "xmark") {
                if viewModel.hasChanges { confirmsDiscard = true } else { dismiss() }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button {
                Task {
                    if await viewModel.save() != nil { savedCount += 1 } else { rejectedCount += 1 }
                }
            } label: {
                if viewModel.isSaving {
                    ProgressView()
                } else {
                    Label("Enregistrer", systemImage: "checkmark")
                }
            }
            .buttonStyle(.glassProminent)
            .tint(.grenier)
            .disabled(!viewModel.hasChanges || viewModel.isSaving)
            .accessibilityHint(viewModel.validationError?.message ?? String(localized: "Enregistre la description, les photos et les zones."))
        }
    }
}

// MARK: - En-tête

/// Couverture, raison sociale, type, vérification et note : en lecture seule.
private struct VendorIdentityHeader: View {
    let vendor: Vendor
    let coverURL: URL?

    @ScaledMetric(relativeTo: .largeTitle) private var coverHeight: CGFloat = 200

    var body: some View {
        cover
            .frame(minHeight: coverHeight)
            .frame(maxWidth: .infinity)
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(vendor.legalName)
                        .font(.title.bold())
                        .fontDesign(.rounded)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { badges }
                        VStack(alignment: .leading, spacing: 6) { badges }
                    }
                }
                .padding(16)
            }
            .clipShape(.rect(cornerRadius: 24))
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var badges: some View {
        badge(Text(vendor.kind.title), systemImage: vendor.kind.systemImage)
        if vendor.isVerified {
            badge(Text("Vérifié"), systemImage: "checkmark.seal.fill")
        }
        if let rating = vendor.averageRating {
            let value = rating.formatted(.number.precision(.fractionLength(1)).locale(AppLanguage.formattingLocale))
            badge(Text(value), systemImage: "star.fill")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Note moyenne \(value) sur 5")
        }
    }

    private func badge(_ text: Text, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).accessibilityHidden(true)
            text
        }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(.ultraThinMaterial.opacity(0.9), in: .capsule)
            .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var cover: some View {
        if let coverURL {
            MediaImage(url: coverURL) { placeholder }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Color.grenier, Color.grenier.opacity(0.7)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: vendor.kind.systemImage)
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(Color.onAccent.opacity(0.5))
                .padding(.bottom, 56)
                .symbolRenderingMode(.hierarchical)
        }
    }
}

// MARK: - Photos

private struct PhotoThumbnail: View {
    let url: URL
    let isCover: Bool

    @ScaledMetric private var side: CGFloat = 96

    var body: some View {
        MediaImage(url: url) { Color.piste.overlay { ProgressView() } }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(alignment: .topLeading) {
            if isCover {
                Image(systemName: "star.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.onAccent)
                    .padding(6)
                    .background(Color.grenier, in: .circle)
                    .padding(6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(isCover ? String(localized: "Photo de couverture") : String(localized: "Photo de vitrine"))
        .accessibilityAddTraits(.isImage)
    }
}

private struct AddPhotoTile: View {
    let isLoading: Bool

    @ScaledMetric private var side: CGFloat = 96

    var body: some View {
        VStack(spacing: 6) {
            if isLoading {
                ProgressView()
            } else {
                Image(systemName: "photo.badge.plus")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                Text("Ajouter")
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(Color.grenier)
        .frame(width: side, height: side)
        .background(Color.grenier.opacity(0.12), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.grenier.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }
        .contentShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Puces de zone

private struct ZoneChip: View {
    enum Style { case selected, suggestion }

    let title: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: style == .selected ? "mappin.circle.fill" : "plus")
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if style == .selected {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .foregroundStyle(style == .selected ? Color.onAccent : Color.grenier)
            .background(style == .selected ? Color.grenier : Color.grenier.opacity(0.12), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(style == .selected ? String(localized: "Retire cette zone.") : String(localized: "Ajoute cette zone."))
    }
}

/// Choix d'un secteur sur la carte : le vendeur déplace la carte sous l'épingle centrale, puis l'ajoute.
private struct ZoneMapPicker: View {
    /// Nom lisible du secteur sous l'épingle (« Villeray », « Secteur de Rosemont »).
    let label: (Double, Double) -> String
    let onPick: (Double, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera: MapCameraPosition = .region(.montreal)
    @State private var center = MKCoordinateRegion.montreal.center

    var body: some View {
        NavigationStack {
            Map(position: $camera, interactionModes: [.pan, .zoom])
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .onMapCameraChange(frequency: .continuous) { context in
                    center = context.region.center
                }
                .overlay {
                    Image(systemName: "mappin.circle.fill")
                        .font(.largeTitle)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.onAccent, Color.grenier)
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 12) {
                        Label(label(center.latitude, center.longitude), systemImage: "building.2.fill")
                            .font(.headline)
                            .foregroundStyle(Color.texte)
                            .contentTransition(.opacity)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .glassEffect(.regular, in: .capsule)
                        Button {
                            onPick(center.latitude, center.longitude)
                            dismiss()
                        } label: {
                            Label("Ajouter ce secteur", systemImage: "plus.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.grenier)
                        .controlSize(.large)
                    }
                    .padding(16)
                }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Choisir un secteur")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer", systemImage: "xmark") { dismiss() }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Carte : déplace-la pour placer l'épingle sur le secteur à desservir")
        }
        .presentationDetents([.large])
    }
}

/// Dispose les puces en lignes, et passe à la ligne quand la place manque (Dynamic Type jusqu'à AX5).
private struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
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

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
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

private extension Vendor {
    /// Contenu du squelette de chargement.
    static let profilePlaceholder = Vendor(
        id: "placeholder", legalName: "Ferme du quartier", kind: .farm,
        description: String(localized: "Légumes cultivés à quelques kilomètres de Montréal."),
        photoURLs: [], servedZones: ["f25d", "f25e"], averageRating: 4.5, isVerified: true
    )
}

// MARK: - Previews

#Preview("Clair") {
    VendorProfileScreen(repositories: .fake(), vendorId: FakeData.ID.fermeRive)
}

#Preview("Sombre") {
    VendorProfileScreen(repositories: .fake(), vendorId: FakeData.ID.fermeRive)
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    VendorProfileScreen(repositories: .fake(), vendorId: FakeData.ID.fermeRive)
        .dynamicTypeSize(.accessibility5)
}

#Preview("Hors ligne") {
    VendorProfileScreen(repositories: .fake(behavior: .failing()), vendorId: FakeData.ID.fermeRive)
}
