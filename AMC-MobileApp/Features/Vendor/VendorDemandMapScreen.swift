// VendorDemandMapScreen.swift
// V3 Carte de la demande (maquette docs/maquettes/V3-demande.png) : où sont les familles prêtes à acheter,
// quartier par quartier. Carte MapKit + bulles, recherche et filtres en verre flottants, feuille du bas
// pour le point choisi, et une liste équivalente pour VoiceOver.

import MapKit
import SwiftUI

private typealias DemandPoint = DemandMapViewModel.DemandPoint

struct VendorDemandMapScreen: View {
    enum DisplayMode: Hashable {
        case map
        case list
    }

    @State private var viewModel: DemandMapViewModel
    /// Action « Proposer un lot ici » ; le bouton est masqué si nil.
    private let onProposeOffer: ((DemandMapViewModel.DemandPoint) -> Void)?

    @State private var displayMode: DisplayMode = .map
    @State private var searchText = ""
    @State private var camera: MapCameraPosition = .region(.montreal)
    @State private var visibleRegion: MKCoordinateRegion = .montreal
    @FocusState private var isSearchFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    @ScaledMetric(relativeTo: .body) private var controlSize: CGFloat = 48

    init(
        repositories: AppRepositories = .fake(),
        vendorId: String = FakeData.ID.fermeRive,
        onProposeOffer: ((DemandMapViewModel.DemandPoint) -> Void)? = nil
    ) {
        _viewModel = State(initialValue: DemandMapViewModel(repositories: repositories, vendorId: vendorId))
        self.onProposeOffer = onProposeOffer
    }

    var body: some View {
        NavigationStack {
            content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.fond.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) { controls }
            .navigationTitle("Demande")
            .navigationBarTitleDisplayMode(.inline)
            .profileToolbar()
        }
        .sheet(isPresented: isSheetPresented) {
            if let point = viewModel.selectedPoint {
                DemandPointSheet(point: point, onProposeOffer: onProposeOffer)
                    .presentationDetents([.fraction(0.35), .medium, .large])
                    .presentationBackgroundInteraction(.enabled)
                    .presentationDragIndicator(.visible)
            }
        }
        .sensoryFeedback(.selection, trigger: viewModel.selectedPointID) { _, new in new != nil }
        .task {
            if voiceOverEnabled { displayMode = .list }
            await viewModel.load()
        }
        .onChange(of: viewModel.points.map(\.id)) { _, _ in
            fitCamera(to: viewModel.points)
        }
        .onChange(of: viewModel.productFilter) { _, productId in
            syncSearchText(with: productId)
        }
        .onChange(of: viewModel.selectedPointID) { _, id in
            isSearchFocused = false
            if let id, let point = viewModel.points.first(where: { $0.id == id }) { focusCamera(on: point) }
        }
    }

    /// La carte reste affichée pendant le chargement (bulles qui apparaissent ensuite) ;
    /// la liste, le vide et l'erreur passent par `StateView`.
    @ViewBuilder private var content: some View {
        if displayMode == .map, isPending || viewModel.state.value != nil {
            mapView(viewModel.points)
                .overlay {
                    if isPending { loadingBadge.transition(.opacity) }
                }
                .animation(reduceMotion ? nil : .smooth, value: isPending)
        } else {
            StateView(
                state: viewModel.state,
                empty: .init(
                    title: "Aucune demande ici",
                    systemImage: "map",
                    message: "Aucun groupe ne s'est encore engagé avec ces filtres. Essaie un autre produit ou toute la demande."
                ),
                retry: { await viewModel.load() }
            ) { points in
                listView(points)
            }
        }
    }

    private var isPending: Bool {
        switch viewModel.state {
        case .idle, .loading: true
        default: false
        }
    }

    private var loadingBadge: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Chargement de la demande…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.texte)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }

    // MARK: Carte

    private func mapView(_ points: [DemandPoint]) -> some View {
        Map(position: $camera, interactionModes: [.pan, .zoom], selection: $viewModel.selectedPointID) {
            ForEach(points) { point in
                if let coordinate = Geohash.decode(point.geohash) {
                    Annotation(point.displayName, coordinate: coordinate, anchor: .center) {
                        DemandBubble(
                            point: point,
                            isSelected: point.id == viewModel.selectedPointID,
                            reduceMotion: reduceMotion
                        ) {
                            select(point)
                        }
                    }
                    .annotationTitles(.hidden)
                    .tag(point.id)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {}
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
        }
        .ignoresSafeArea(edges: [.top, .bottom])
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Carte de la demande à Montréal")
    }

    // MARK: Liste accessible

    private func listView(_ points: [DemandPoint]) -> some View {
        List(points) { point in
            Button {
                select(point)
            } label: {
                DemandRow(point: point)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.surface)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(point.accessibilityDescription)
            .accessibilityHint("Affiche les produits voulus")
            .accessibilityAddTraits(point.id == viewModel.selectedPointID ? [.isButton, .isSelected] : .isButton)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .contentMargins(.top, 8, for: .scrollContent)
    }

    // MARK: Contrôles en verre (recherche, filtres, carte ou liste)

    private var controls: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    searchField
                    filterMenu
                    displayModeToggle
                }
                if isSearchFocused, !suggestions.isEmpty {
                    suggestionChips
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .animation(reduceMotion ? nil : .smooth, value: isSearchFocused)
        .animation(reduceMotion ? nil : .smooth, value: suggestions.map(\.id))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Chercher un produit", text: $searchText)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit(applyFirstSuggestion)
                .onChange(of: searchText) { _, text in
                    let selectedName = viewModel.availableProducts.first { $0.productId == viewModel.productFilter }?.name
                    if text != selectedName { viewModel.productFilter = nil }
                }
            if !searchText.isEmpty {
                Button("Effacer la recherche", systemImage: "xmark.circle.fill") {
                    searchText = ""
                    viewModel.productFilter = nil
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
            }
        }
        .font(.body)
        .padding(.horizontal, 16)
        .frame(minHeight: controlSize)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var filterMenu: some View {
        Menu {
            Picker("Regrouper par", selection: $viewModel.grouping) {
                ForEach(DemandMapViewModel.Grouping.allCases) { Text($0.title).tag($0) }
            }
            Picker("Lots", selection: $viewModel.scope) {
                ForEach(DemandMapViewModel.Scope.allCases) { Text($0.title).tag($0) }
            }
            Picker("Produit", selection: $viewModel.productFilter) {
                Text("Tous les produits").tag(String?.none)
                ForEach(viewModel.availableProducts) { product in
                    Text(product.name).tag(String?.some(product.productId))
                }
            }
            .pickerStyle(.menu)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.body.weight(.semibold))
                .foregroundStyle(hasActiveFilters ? Color.onAccent : Color.texte)
                .frame(width: controlSize, height: controlSize)
                .contentShape(.circle)
        }
        .glassEffect(hasActiveFilters ? .regular.tint(.grenier).interactive() : .regular.interactive(), in: .circle)
        .accessibilityLabel("Filtres")
        .accessibilityValue(filterSummary)
    }

    private var displayModeToggle: some View {
        Button {
            withAnimation(reduceMotion ? nil : .smooth) {
                displayMode = displayMode == .map ? .list : .map
            }
        } label: {
            Image(systemName: displayMode == .map ? "list.bullet" : "map")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.texte)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: controlSize, height: controlSize)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(displayMode == .map ? "Afficher la liste des quartiers" : "Afficher la carte")
    }

    private var suggestionChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(suggestions) { product in
                    Button {
                        apply(product)
                    } label: {
                        Text(product.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.texte)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .accessibilityHint("Filtre la carte sur ce produit")
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    // MARK: Logique de vue

    private var isSheetPresented: Binding<Bool> {
        Binding {
            viewModel.selectedPoint != nil
        } set: { isPresented in
            if !isPresented { viewModel.selectedPointID = nil }
        }
    }

    private var suggestions: [DemandMapViewModel.ProductDemand] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let products = viewModel.availableProducts
        guard !query.isEmpty else { return products }
        return products.filter { $0.name.localizedStandardContains(query) && $0.productId != viewModel.productFilter }
    }

    private var hasActiveFilters: Bool {
        viewModel.productFilter != nil || viewModel.scope != .allOffers || viewModel.grouping != .neighborhood
    }

    private var filterSummary: String {
        var parts = [viewModel.grouping.title, viewModel.scope.title]
        if let name = viewModel.availableProducts.first(where: { $0.productId == viewModel.productFilter })?.name {
            parts.append(name)
        }
        return parts.joined(separator: ", ")
    }

    /// Sélection depuis la liste ou VoiceOver (sur la carte, MapKit gère le toucher via `selection`).
    private func select(_ point: DemandPoint) {
        withAnimation(reduceMotion ? nil : .smooth) {
            viewModel.selectedPointID = point.id
        }
    }

    private func focusCamera(on point: DemandPoint) {
        guard displayMode == .map, let coordinate = Geohash.decode(point.geohash) else { return }
        // Garde la bulle dans le tiers haut, au-dessus de la feuille du bas.
        let span = visibleRegion.span
        let center = CLLocationCoordinate2D(latitude: coordinate.latitude - span.latitudeDelta * 0.18, longitude: coordinate.longitude)
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.6)) {
            camera = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    private func apply(_ product: DemandMapViewModel.ProductDemand) {
        viewModel.productFilter = product.productId
        searchText = product.name
        isSearchFocused = false
    }

    private func applyFirstSuggestion() {
        if let first = suggestions.first, !searchText.isEmpty { apply(first) }
    }

    private func syncSearchText(with productId: String?) {
        if let productId, let product = viewModel.availableProducts.first(where: { $0.productId == productId }) {
            searchText = product.name
        } else if productId == nil, viewModel.availableProducts.contains(where: { $0.name == searchText }) {
            searchText = ""
        }
    }

    private func fitCamera(to points: [DemandPoint]) {
        let coordinates = points.compactMap { Geohash.decode($0.geohash) }
        guard let region = MKCoordinateRegion(fitting: coordinates) else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.8)) {
            camera = .region(region)
        }
        visibleRegion = region
    }
}

// MARK: - Bulle de la carte

private struct DemandBubble: View {
    let point: DemandPoint
    let isSelected: Bool
    let reduceMotion: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var minimumDiameter: CGFloat = 48
    @ScaledMetric(relativeTo: .body) private var maximumDiameter: CGFloat = 96

    /// Aire proportionnelle aux parts engagées (intensité de 0 à 1), bornée pour rester lisible à AX5.
    private var diameter: CGFloat {
        let low = min(minimumDiameter, 72)
        let high = max(min(maximumDiameter, 128), low)
        return low + (high - low) * CGFloat(point.intensity.squareRoot())
    }

    var body: some View {
        Text(point.committedHouseholds, format: .number)
            .font(point.isHighDemand ? .title2.bold() : .headline)
            .fontDesign(.rounded)
            .monospacedDigit()
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .foregroundStyle(point.isHighDemand ? Color.onAccent : Color.grenier)
            .padding(6)
            .frame(width: diameter, height: diameter)
            .background {
                Circle().fill(point.isHighDemand ? Color.grenier.opacity(0.9) : Color.grenier.opacity(0.16))
            }
            .overlay {
                Circle().strokeBorder(
                    isSelected ? Color.texte : Color.grenier.opacity(point.isHighDemand ? 1 : 0.55),
                    lineWidth: isSelected ? 3 : 1.5
                )
            }
            .shadow(color: .black.opacity(isSelected ? 0.18 : 0.06), radius: isSelected ? 10 : 4, y: 2)
            .scaleEffect(isSelected && !reduceMotion ? 1.08 : 1)
            .contentShape(.circle)
            .overlay(alignment: .bottom) {
                Text(point.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.texte)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.surface, in: .capsule)
                    .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                    .alignmentGuide(.bottom) { dimensions in dimensions[.top] - 4 }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.3), value: isSelected)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(point.accessibilityDescription)
            .accessibilityHint("Affiche les produits voulus")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { action() }
    }
}

// MARK: - Ligne de la liste

private struct DemandRow: View {
    let point: DemandPoint
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var dotSize: CGFloat = 40

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Text(point.committedHouseholds, format: .number)
                .font(.headline)
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(point.isHighDemand ? Color.onAccent : Color.grenier)
                .frame(minWidth: dotSize, minHeight: dotSize)
                .background(point.isHighDemand ? Color.grenier : Color.grenier.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(point.displayName)
                    .font(.headline)
                    .foregroundStyle(Color.texte)
                Text(point.summary)
                    .font(.subheadline)
                    .foregroundStyle(Color.texteSecondaire)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            if point.isHighDemand { HighDemandBadge() }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}

// MARK: - Feuille du point choisi

private struct DemandPointSheet: View {
    let point: DemandPoint
    let onProposeOffer: ((DemandPoint) -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                productsCard
                if let onProposeOffer {
                    Button {
                        onProposeOffer(point)
                    } label: {
                        Label("Proposer un lot ici", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.grenier)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var header: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return VStack(alignment: .leading, spacing: 4) {
            layout {
                Text(point.displayName)
                    .font(.title.bold())
                    .foregroundStyle(Color.texte)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                if point.isHighDemand { HighDemandBadge() }
            }
            Text(point.summary)
                .font(.subheadline)
                .foregroundStyle(Color.texteSecondaire)
        }
    }

    private var productsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Produits voulus")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.texteSecondaire)
                .textCase(.uppercase)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            ForEach(point.products, id: \.productId) { (product: DemandMapViewModel.ProductDemand) in
                if product.productId != point.products.first?.productId {
                    Rectangle().fill(Color.piste).frame(height: 1).accessibilityHidden(true)
                }
                ProductDemandRow(product: product)
            }
        }
        .grenierCard()
    }
}

private struct ProductDemandRow: View {
    let product: DemandMapViewModel.ProductDemand
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            Text(product.name)
                .font(.body)
                .foregroundStyle(Color.texte)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(DemandFormatting.wantedQuantity(of: product))
                .font(.body.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(Color.texte)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

private struct HighDemandBadge: View {
    var body: some View {
        Text("Forte demande")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.onAccent)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Color.grenier, in: .capsule)
            .fixedSize()
    }
}

// MARK: - Textes

/// Formulations de V3 (testées dans `DemandMapFormattingTests`).
nonisolated enum DemandFormatting {
    /// « 1 famille », « 24 familles ».
    static func families(_ count: Int) -> String {
        "\(count.formatted()) \(count > 1 ? "familles" : "famille")"
    }

    /// « 1 part », « 26 parts ».
    static func shares(_ count: Int) -> String {
        "\(count.formatted()) \(count > 1 ? "parts" : "part")"
    }

    /// « 260 kg voulus » si l'unité de part contient un poids (« sac de 10 kg »), sinon « 26 parts voulues ».
    static func wantedQuantity(of product: DemandMapViewModel.ProductDemand) -> String {
        if let kilograms = kilogramsPerShare(in: product.shareUnit) {
            let total = kilograms * Double(product.committedShares)
            return "\(total.formatted(.number.precision(.fractionLength(0...1)))) kg voulus"
        }
        return "\(shares(product.committedShares)) \(product.committedShares > 1 ? "voulues" : "voulue")"
    }

    /// Kilos par part lus dans l'unité (« sac de 10 kg » → 10, « caisse de 2,5 kg » → 2,5).
    static func kilogramsPerShare(in unit: String) -> Double? {
        guard let match = unit.firstMatch(of: /(\d+(?:[.,]\d+)?)\s*kg\b/) else { return nil }
        return Double(match.1.replacingOccurrences(of: ",", with: "."))
    }
}

extension DemandMapViewModel.DemandPoint {
    /// Nom affiché : « Zone f25d » pour un geohash, sinon le quartier ou le groupe.
    var displayName: String {
        grouping == .geohash ? "Zone \(label)" : label
    }

    /// « 24 familles · 26 parts ».
    var summary: String {
        "\(DemandFormatting.families(committedHouseholds)) · \(DemandFormatting.shares(committedShares))"
    }

    /// « Parc-Ex Ouest, 24 familles, forte demande ».
    var accessibilityDescription: String {
        var parts = [displayName, DemandFormatting.families(committedHouseholds)]
        if isHighDemand { parts.append("forte demande") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Montréal

extension MKCoordinateRegion {
    /// Île de Montréal, du Plateau à Parc-Extension.
    static let montreal = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 45.5260, longitude: -73.6000),
        span: MKCoordinateSpan(latitudeDelta: 0.14, longitudeDelta: 0.14)
    )

    /// Région qui contient tous les points, avec de la marge pour les bulles et la feuille du bas ; nil si aucun point.
    init?(fitting coordinates: [CLLocationCoordinate2D]) {
        guard let first = coordinates.first else { return nil }
        var minLatitude = first.latitude, maxLatitude = first.latitude
        var minLongitude = first.longitude, maxLongitude = first.longitude
        for coordinate in coordinates.dropFirst() {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }
        let latitudeDelta = max((maxLatitude - minLatitude) * 1.9, 0.05)
        let longitudeDelta = max((maxLongitude - minLongitude) * 1.6, 0.05)
        // Centre un peu plus bas que le milieu : les contrôles du haut couvrent le haut de la carte.
        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2 + latitudeDelta * 0.06,
            longitude: (minLongitude + maxLongitude) / 2
        )
        self.init(center: center, span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta))
    }
}

// MARK: - Previews

#Preview("Clair") {
    VendorDemandMapScreen(repositories: .fake(data: .demandMapDemo)) { _ in }
}

#Preview("Sombre") {
    VendorDemandMapScreen(repositories: .fake(data: .demandMapDemo)) { _ in }
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    VendorDemandMapScreen(repositories: .fake(data: .demandMapDemo)) { _ in }
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Jeu fake de base") {
    VendorDemandMapScreen()
}

#Preview("Erreur") {
    VendorDemandMapScreen(repositories: .fake(behavior: .failing(.offline)))
}
