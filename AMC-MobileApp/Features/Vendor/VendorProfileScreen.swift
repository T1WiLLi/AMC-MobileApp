import PhotosUI
import SwiftUI

/// Profil vendeur (T-076, RQ-016) : vitrine (photos), raison sociale et type en lecture seule,
/// description et zones desservies modifiables. Présenté en feuille depuis le Tableau de bord vendeur.
struct VendorProfileScreen: View {
    @State private var viewModel: VendorProfileViewModel
    @State private var pickedItem: PhotosPickerItem?
    @State private var zoneDraft = ""
    @State private var fieldError: AppError?
    @State private var savedCount = 0
    @State private var rejectedCount = 0
    @State private var confirmsDiscard = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        repositories: AppRepositories = .fake(),
        vendorId: String = FakeData.ID.fermeRive,
        photoStore: any VendorPhotoStoring = LocalVendorPhotoStore()
    ) {
        _viewModel = State(initialValue: VendorProfileViewModel(
            repositories: repositories, vendorId: vendorId, photoStore: photoStore
        ))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Profil vendeur")
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
                        PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                            AddPhotoTile(isLoading: viewModel.isAddingPhoto)
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
            Label("Vitrine", systemImage: "photo.on.rectangle.angled")
        } footer: {
            Text("La première photo sert de couverture sur tes lots. Touche longuement une photo pour la gérer · \(viewModel.photoURLs.count) sur \(VendorProfileViewModel.maxPhotos).")
        }
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
                Text("Les familles la lisent sur chaque lot.")
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

    // MARK: - Zones

    private var zonesSection: some View {
        Section {
            if viewModel.servedZones.isEmpty {
                Label("Aucune zone : tes lots n'apparaissent nulle part.", systemImage: "mappin.slash")
                    .foregroundStyle(.secondary)
            } else {
                ChipFlow {
                    ForEach(viewModel.servedZones, id: \.self) { zone in
                        ZoneChip(title: viewModel.label(forZone: zone), code: zone, style: .selected) {
                            withGrenierAnimation(.snappy, reduceMotion: reduceMotion) { viewModel.removeZone(zone) }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if !viewModel.zoneSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quartiers des groupes")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ChipFlow {
                        ForEach(viewModel.zoneSuggestions) { option in
                            ZoneChip(title: option.label, code: option.id, style: .suggestion) {
                                addZone(option.id)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            HStack {
                TextField("Autre zone (code geohash, ex. f25d)", text: $zoneDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { addZone(zoneDraft) }
                Button("Ajouter", systemImage: "plus.circle.fill") { addZone(zoneDraft) }
                    .labelStyle(.iconOnly)
                    .imageScale(.large)
                    .disabled(zoneDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let fieldError {
                Label(fieldError.message, systemImage: fieldError.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        } header: {
            Label("Zones desservies", systemImage: "map.fill")
        } footer: {
            Text("Tes nouveaux lots sont proposés aux familles de ces zones. \(viewModel.servedZones.count) sur \(VendorProfileViewModel.maxZones).")
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

    @ScaledMetric(relativeTo: .largeTitle) private var coverHeight: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cover
                .frame(height: coverHeight)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 24))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(vendor.legalName)
                    .font(.title2.bold())
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { badges }
                    VStack(alignment: .leading, spacing: 6) { badges }
                }
                Label("Raison sociale et type : modifiables par l'équipe Grenier.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var badges: some View {
        Label(vendor.kind.title, systemImage: vendor.kind.systemImage)
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(Color.grenier.opacity(0.12), in: .capsule)
            .foregroundStyle(Color.grenier)
        if vendor.isVerified {
            Label("Vérifié", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.economie)
        }
        if let rating = vendor.averageRating {
            Label(rating.formatted(.number.precision(.fractionLength(1))) + " / 5", systemImage: "star.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Note moyenne \(rating.formatted(.number.precision(.fractionLength(1)))) sur 5")
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let coverURL {
            AsyncImage(url: coverURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Color.grenier.opacity(0.25), Color.grenier.opacity(0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: vendor.kind.systemImage)
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(Color.grenier)
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
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Color.piste.overlay { ProgressView() }
            }
        }
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
    let code: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: style == .selected ? "mappin.circle.fill" : "plus")
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if title != code {
                    Text(code)
                        .font(.caption.monospaced())
                        .foregroundStyle(style == .selected ? Color.onAccent.opacity(0.8) : .secondary)
                }
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
        .accessibilityLabel(title == code ? String(localized: "Zone \(code)") : String(localized: "\(title), zone \(code)"))
        .accessibilityHint(style == .selected ? String(localized: "Retire cette zone.") : String(localized: "Ajoute cette zone."))
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
    VendorProfileScreen()
}

#Preview("Sombre") {
    VendorProfileScreen()
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    VendorProfileScreen()
        .dynamicTypeSize(.accessibility5)
}

#Preview("Hors ligne") {
    VendorProfileScreen(repositories: .fake(behavior: .failing()))
}
