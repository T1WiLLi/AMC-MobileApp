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
        repositories: AppRepositories,
        vendorId: String,
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
            .infoToolbarButton(.vendorDemand)
            .toolbar {
                // B-055 : une carte ne se tire pas ; la liste a aussi « tirer pour rafraîchir ».
                ToolbarItem(placement: .topBarLeading) {
                    Button("Actualiser", systemImage: "arrow.clockwise") {
                        Task { await viewModel.refresh() }
                    }
                    .symbolEffect(.rotate, options: .speed(2), isActive: viewModel.isRefreshing && !reduceMotion)
                    .disabled(isPending || viewModel.isRefreshing)
                }
            }
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
            // B-055 : pas de second chargement (squelette) en revenant sur l'onglet, seulement un rafraîchissement.
            guard case .idle = viewModel.state else {
                await viewModel.refresh()
                return
            }
            if voiceOverEnabled { displayMode = .list }
            await viewModel.load()
            // Centre la carte sur la demande réelle, même si les ids n'ont pas changé (rechargement).
            fitCamera(to: viewModel.points)
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
                    systemImage: "binoculars.fill",
                    message: "Cet écran montre où les familles commandent et ce qu'elles souhaitent acheter. Avec ces filtres, personne n'a encore de demande : essaie un autre produit ou toute la demande.",
                    action: hasActiveFilters ? EmptyStateAction(title: "Voir toute la demande", systemImage: "line.3.horizontal.decrease.circle") {
                        viewModel.productFilter = nil
                        viewModel.scope = .allOffers
                    } : nil
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
            Image(systemName: "map.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .symbolEffect(.pulse, isActive: !reduceMotion)
                .accessibilityHidden(true)
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
                if let coordinate = point.coordinate {
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
        .accessibilityLabel("Carte de la demande")
    }

    // MARK: Liste accessible

    private func listView(_ points: [DemandPoint]) -> some View {
        List {
            Section {
                DemandListHero(points: points, grouping: viewModel.grouping)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(points) { point in
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
            } header: {
                Label("\(viewModel.grouping.title) par demande", systemImage: "chart.bar.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await viewModel.refresh() }
        .grenierScrollEdge()
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
                } else if displayMode == .map, let points = viewModel.state.value {
                    DemandSummaryStrip(points: points)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .guidedTourAnchor(.vendorDemand, padding: 6)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .animation(reduceMotion ? nil : .smooth, value: isSearchFocused)
        .animation(reduceMotion ? nil : .smooth, value: suggestions.map(\.id))
        .animation(reduceMotion ? nil : .smooth, value: displayMode)
        .sensoryFeedback(.selection, trigger: displayMode)
        .sensoryFeedback(.selection, trigger: filterSummary)
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
            Picker(selection: $viewModel.grouping) {
                ForEach(DemandMapViewModel.Grouping.allCases) { grouping in
                    Label(grouping.title, systemImage: grouping.systemImage).tag(grouping)
                }
            } label: {
                Label("Regrouper par", systemImage: "square.stack.3d.up.fill")
            }
            Picker(selection: $viewModel.scope) {
                ForEach(DemandMapViewModel.Scope.allCases) { scope in
                    Label(scope.title, systemImage: scope.systemImage).tag(scope)
                }
            } label: {
                Label("Lots", systemImage: "shippingbox.fill")
            }
            Picker(selection: $viewModel.productFilter) {
                Label("Tous les produits", systemImage: "square.grid.2x2.fill").tag(String?.none)
                ForEach(viewModel.availableProducts) { product in
                    Label(product.name, systemImage: "basket.fill").tag(String?.some(product.productId))
                }
            } label: {
                Label("Produit", systemImage: "basket.fill")
            }
            .pickerStyle(.menu)
        } label: {
            Image(systemName: hasActiveFilters
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "slider.horizontal.3")
                .font(.body.weight(.semibold))
                .contentTransition(.symbolEffect(.replace))
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
        .accessibilityLabel(displayMode == .map ? String(localized: "Afficher la liste des quartiers") : String(localized: "Afficher la carte"))
    }

    private var suggestionChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(suggestions) { product in
                    Button {
                        apply(product)
                    } label: {
                        Label {
                            Text(product.name)
                                .foregroundStyle(Color.texte)
                        } icon: {
                            Image(systemName: "basket.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.grenier)
                        }
                            .font(.subheadline.weight(.semibold))
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
        guard displayMode == .map, let coordinate = point.coordinate else { return }
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
        let coordinates = points.compactMap(\.coordinate)
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
        VStack(spacing: 0) {
            if point.isHighDemand {
                Image(systemName: "flame.fill")
                    .font(.caption.bold())
                    .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : isSelected)
            }
            Text(point.interestedHouseholds, format: .number)
                .font(point.isHighDemand ? .title2.bold() : .headline)
                .fontDesign(.rounded)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
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

    // B-041 : rangée lisible (quartier, familles, parts, produit principal) et jauge horizontale fine,
    // au lieu de la pilule « Forte demande » qui mangeait la moitié de la carte.
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                Text(point.interestedHouseholds, format: .number)
                    .font(.headline)
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(point.isHighDemand ? Color.onAccent : Color.grenier)
                    .frame(width: dotSize, height: dotSize)
                    .background(point.isHighDemand ? Color.grenier : Color.grenier.opacity(0.14), in: .circle)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Label(point.displayName, systemImage: point.grouping.systemImage)
                        .font(.headline)
                        .foregroundStyle(Color.texte)
                        .symbolRenderingMode(.hierarchical)
                    if point.isHighDemand {
                        Image(systemName: "flame.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.grenier)
                            .accessibilityLabel("Forte demande")
                    }
                }
                Label(point.summary, systemImage: "person.2.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.texteSecondaire)
                    .symbolRenderingMode(.hierarchical)
                if let top = point.products.first {
                    Label("Surtout : \(top.name)", systemImage: "basket.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.texteSecondaire)
                        .symbolRenderingMode(.hierarchical)
                        .lineLimit(2)
                }
                DemandGauge(intensity: point.intensity, isHigh: point.isHighDemand)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.texteSecondaire)
                .frame(minHeight: dotSize)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
    }
}

/// Jauge horizontale de l'intensité de la demande (0 à 1, relative au point le plus demandé).
private struct DemandGauge: View {
    let intensity: Double
    let isHigh: Bool

    var body: some View {
        Capsule()
            .fill(Color.grenier.opacity(0.14))
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(isHigh ? Color.grenier : Color.grenier.opacity(0.6))
                        .frame(width: max(6, proxy.size.width * min(max(intensity, 0), 1)))
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Feuille du point choisi

/// Aussi ouverte depuis la recherche du portail Vendeur (T-129).
struct DemandPointSheet: View {
    let point: DemandMapViewModel.DemandPoint
    var onProposeOffer: ((DemandMapViewModel.DemandPoint) -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var tileSide: CGFloat = 52
    @State private var hasAppeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statsRow
                if !point.products.isEmpty { productsCard }
                if !point.wishes.isEmpty { wishesCard }
                if let onProposeOffer {
                    Button {
                        onProposeOffer(point)
                    } label: {
                        Label("Proposer un lot ici", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .symbolEffect(.wiggle, options: .nonRepeating, value: reduceMotion ? false : hasAppeared)
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
        .onAppear { hasAppeared = true }
    }

    private var header: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return VStack(alignment: .leading, spacing: 4) {
            layout {
                Image(systemName: point.grouping.systemImage)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
                    .frame(width: min(tileSide, 80), height: min(tileSide, 80))
                    .background(Color.grenier.opacity(0.12), in: .rect(cornerRadius: 14))
                    .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : hasAppeared)
                    .accessibilityHidden(true)
                Text(point.displayName)
                    .font(.title.bold())
                    .foregroundStyle(Color.texte)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                if point.isHighDemand { HighDemandBadge() }
            }
        }
    }

    /// Trois chiffres clés du point : familles engagées, parts, ménages membres.
    private var statsRow: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        return layout {
            GrenierStatTile(
                point.committedHouseholds.formatted(.number.locale(AppLanguage.formattingLocale)),
                systemImage: "person.2.fill",
                tint: .grenier,
                caption: Text(FrenchPlural.word(point.committedHouseholds, String(localized: "famille engagée"), plural: String(localized: "familles engagées"))),
                numericValue: Double(point.committedHouseholds)
            )
            GrenierStatTile(
                point.committedShares.formatted(.number.locale(AppLanguage.formattingLocale)),
                systemImage: "shippingbox.fill",
                tint: .economie,
                caption: Text(FrenchPlural.word(point.committedShares, "part")),
                numericValue: Double(point.committedShares)
            )
            if point.wishingHouseholds > 0 {
                GrenierStatTile(
                    point.wishingHouseholds.formatted(.number.locale(AppLanguage.formattingLocale)),
                    systemImage: "heart.fill",
                    tint: .solidarite,
                    caption: Text(FrenchPlural.word(point.wishingHouseholds, "famille intéressée", plural: "familles intéressées")),
                    numericValue: Double(point.wishingHouseholds)
                )
            } else {
                GrenierStatTile(
                    point.householdCount.formatted(.number.locale(AppLanguage.formattingLocale)),
                    systemImage: "house.fill",
                    tint: .solidarite,
                    caption: Text(FrenchPlural.word(point.householdCount, "membre")),
                    numericValue: Double(point.householdCount)
                )
            }
        }
        // Les trois tuiles prennent la hauteur de la plus haute.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Envies des familles (S-07) : anonymes, par catégorie et unité.
    private var wishesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Envies des familles", systemImage: "heart.text.square.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.texteSecondaire)
                .symbolRenderingMode(.hierarchical)
                .textCase(.uppercase)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            ForEach(point.wishes) { demand in
                if demand.id != point.wishes.first?.id {
                    Rectangle().fill(Color.piste).frame(height: 1).accessibilityHidden(true)
                }
                WishDemandRow(demand: demand)
            }
        }
        .grenierCard()
    }

    private var productsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Produits voulus", systemImage: "basket.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.texteSecondaire)
                .symbolRenderingMode(.hierarchical)
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

/// « Céréales · 3 familles · 30 kg ».
private struct WishDemandRow: View {
    let demand: GroupDemand
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(demand.category.title)
                        .foregroundStyle(Color.texte)
                    Text(DemandFormatting.families(demand.householdCount))
                        .font(.subheadline)
                        .foregroundStyle(Color.texteSecondaire)
                }
            } icon: {
                Image(systemName: ProductIcon.symbol(for: demand.category))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.solidarite)
            }
            .font(.body)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(DemandFormatting.wishQuantity(of: demand))
                .font(.body.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(Color.texte)
                // La quantité reste sur une ligne : c'est le nom du produit qui passe à la ligne, pas « parts / voulues ».
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
                .layoutPriority(1)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
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
            Label {
                Text(product.name)
                    .foregroundStyle(Color.texte)
            } icon: {
                Image(systemName: "shippingbox.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
            }
            .font(.body)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Label(DemandFormatting.wantedQuantity(of: product), systemImage: "scalemass.fill")
                .labelStyle(.titleAndIcon)
                .symbolRenderingMode(.hierarchical)
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
        Label("Forte demande", systemImage: "flame.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.onAccent)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Color.grenier, in: .capsule)
            .fixedSize()
    }
}

// MARK: - Résumé de la demande

/// Totaux de la demande affichée, pour le bandeau en verre et l'en-tête de la liste.
private struct DemandTotals {
    let households: Int
    let shares: Int
    let highDemandCount: Int

    init(_ points: [DemandPoint]) {
        households = points.reduce(0) { $0 + $1.interestedHouseholds }
        shares = points.reduce(0) { $0 + $1.committedShares }
        highDemandCount = points.filter(\.isHighDemand).count
    }

    var accessibilityDescription: String {
        var parts = [DemandFormatting.families(households), DemandFormatting.shares(shares)]
        if highDemandCount > 0 {
            parts.append(String(localized: "\(highDemandCount) en forte demande"))
        }
        return parts.joined(separator: ", ")
    }
}

/// Bandeau en verre sous la recherche, sur la carte : familles, parts, points en forte demande.
private struct DemandSummaryStrip: View {
    let points: [DemandPoint]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let totals = DemandTotals(points)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 14))
        layout {
            item(totals.households, systemImage: "person.2.fill", tint: .grenier)
            item(totals.shares, systemImage: "shippingbox.fill", tint: .economie)
            if totals.highDemandCount > 0 {
                item(totals.highDemandCount, systemImage: "flame.fill", tint: .grenier)
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Demande affichée : \(totals.accessibilityDescription)")
    }

    private func item(_ value: Int, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .symbolEffect(.bounce, options: .nonRepeating, value: value)
            Text(value, format: .number)
                .fontDesign(.rounded)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
                .foregroundStyle(Color.texte)
        }
    }
}

/// En-tête de la liste : petite scène de carte et totaux de la demande.
private struct DemandListHero: View {
    let points: [DemandPoint]
    let grouping: DemandMapViewModel.Grouping
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let totals = DemandTotals(points)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            GrenierSymbolScene(
                symbol: "map.fill",
                satellites: [.init("person.2.fill"), .init("flame.fill"), .init("basket.fill", tint: .economie)],
                trigger: totals.shares
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(DemandFormatting.families(totals.households))
                    .font(.title2.bold())
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.texte)
                    .contentTransition(.numericText(value: Double(totals.households)))
                Text("prêtes à acheter · \(DemandFormatting.shares(totals.shares))")
                    .font(.subheadline)
                    .foregroundStyle(Color.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                if totals.highDemandCount > 0 {
                    Label(
                        String(localized: "\(totals.highDemandCount) \(FrenchPlural.word(totals.highDemandCount, grouping.unitName, plural: grouping.unitNamePlural)) en forte demande"),
                        systemImage: "flame.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.grenier)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .grenierCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Demande affichée : \(totals.accessibilityDescription)")
    }
}

// MARK: - Icônes des filtres

extension DemandMapViewModel.Grouping {
    /// Symbole du niveau d'agrégation (menu des filtres, lignes, feuille).
    var systemImage: String {
        switch self {
        case .group: "person.3.fill"
        case .neighborhood: "building.2.fill"
        case .geohash: "square.grid.3x3.fill"
        }
    }

    /// « groupe », « quartier », « zone ».
    fileprivate var unitName: String {
        switch self {
        case .group: String(localized: "groupe")
        case .neighborhood: String(localized: "quartier")
        case .geohash: String(localized: "zone")
        }
    }

    fileprivate var unitNamePlural: String { unitName + "s" }
}

extension DemandMapViewModel.Scope {
    /// Symbole du périmètre des lots.
    var systemImage: String {
        switch self {
        case .allOffers: "globe.americas.fill"
        case .myOffers: "storefront.fill"
        }
    }
}

// MARK: - Textes

/// Formulations de V3 (testées dans `DemandMapFormattingTests`).
nonisolated enum DemandFormatting {
    /// « 1 famille », « 24 familles ».
    static func families(_ count: Int) -> String {
        "\(count.formatted(.number.locale(AppLanguage.formattingLocale))) \(FrenchPlural.word(count, "famille", plural: "familles"))"
    }

    /// « 1 part », « 26 parts ».
    static func shares(_ count: Int) -> String {
        "\(count.formatted(.number.locale(AppLanguage.formattingLocale))) \(FrenchPlural.word(count, "part", plural: "parts"))"
    }

    /// « 260 kg voulus » si l'unité de part contient un poids (« sac de 10 kg »), sinon « 26 parts voulues ».
    static func wantedQuantity(of product: DemandMapViewModel.ProductDemand) -> String {
        if let kilograms = kilogramsPerShare(in: product.shareUnit) {
            let total = kilograms * Double(product.committedShares)
            return String(localized: "\(total.formatted(.number.precision(.fractionLength(0...1)).locale(AppLanguage.formattingLocale))) kg voulus")
        }
        return "\(shares(product.committedShares)) \(FrenchPlural.word(product.committedShares, "voulue", plural: "voulues"))"
    }

    /// « 30 kg », « 4 douzaines », « 2,5 L » : total voulu d'une envie agrégée.
    static func wishQuantity(of demand: GroupDemand) -> String {
        let number = demand.totalQuantity.formatted(.number.precision(.fractionLength(0...1)).locale(AppLanguage.formattingLocale))
        let unit = switch demand.unit {
        case .dozen: FrenchPlural.word(Int(demand.totalQuantity.rounded(.up)), "douzaine", plural: "douzaines")
        case .unit: FrenchPlural.word(Int(demand.totalQuantity.rounded(.up)), "unité", plural: "unités")
        case .kilogram, .liter: demand.unit.title
        }
        return "\(number) \(unit)"
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
        switch grouping {
        case .geohash: String(localized: "Zone \(label)")
        // Le quartier est stocké en identifiant (« parc-extension ») : on affiche « Parc-Extension ».
        case .neighborhood: MontrealNeighborhood.displayName(for: label)
        case .group: label
        }
    }

    /// « 24 familles · 26 parts ».
    var summary: String {
        "\(DemandFormatting.families(interestedHouseholds)) · \(DemandFormatting.shares(committedShares))"
    }

    /// « Parc-Ex Ouest, 24 familles, forte demande ».
    var accessibilityDescription: String {
        var parts = [displayName, DemandFormatting.families(interestedHouseholds)]
        if isHighDemand { parts.append(String(localized: "forte demande")) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Position des bulles

nonisolated extension DemandMapViewModel.DemandPoint {
    /// Écart au-delà duquel le centre d'un groupe ne colle plus à son quartier (geohash tronqué ou mal saisi).
    static let neighborhoodToleranceMeters: Double = 1_500

    /// Où poser la bulle. Le centre d'un groupe est souvent un geohash à 5 caractères (≈ 5 km) : décodé tel quel,
    /// « Saint-Michel » (f25dv) tombait près du Mont-Royal et « Hochelaga » (f25ej) sur le Plateau.
    /// - « Quartiers » : toujours le centre connu du quartier (`MontrealNeighborhood`).
    /// - « Groupes » : le centre du groupe s'il est dans son quartier, sinon le centre du quartier.
    /// - « Zones », ou quartier inconnu : le centre du geohash.
    var coordinate: CLLocationCoordinate2D? {
        let decoded = Geohash.decode(geohash)
        guard grouping != .geohash else { return decoded }
        let name = grouping == .neighborhood ? label : (neighborhood ?? "")
        guard let known = MontrealNeighborhood.named(MontrealNeighborhood.displayName(for: name)) else { return decoded }
        let center = CLLocationCoordinate2D(latitude: known.latitude, longitude: known.longitude)
        guard grouping == .group, let decoded else { return center }
        let gap = Geohash.distanceMeters(from: Geohash.Coordinate(decoded), to: Geohash.Coordinate(center))
        return gap <= Self.neighborhoodToleranceMeters ? decoded : center
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

#if DEBUG
#Preview("Clair") {
    VendorDemandMapScreen(repositories: .fake(data: .demandMapDemo), vendorId: FakeData.ID.fermeRive) { _ in }
}

#Preview("Sombre") {
    VendorDemandMapScreen(repositories: .fake(data: .demandMapDemo), vendorId: FakeData.ID.fermeRive) { _ in }
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    VendorDemandMapScreen(repositories: .fake(data: .demandMapDemo), vendorId: FakeData.ID.fermeRive) { _ in }
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Jeu fake de base") {
    VendorDemandMapScreen(repositories: .fake(), vendorId: FakeData.ID.fermeRive)
}

#Preview("Erreur") {
    VendorDemandMapScreen(repositories: .fake(behavior: .failing(.offline)), vendorId: FakeData.ID.fermeRive)
}
#endif
