// FamilyMapScreen.swift
// Carte pour les familles (T-091, spec S-02) : groupes, points de cueillette et producteurs autour de chez soi.
// Poussée depuis l'onglet Groupes (bouton carte de la barre d'outils) : les routes `GroupRoute` et `OfferRoute`
// sont celles du NavigationStack de l'onglet.
//
// Couches : carte MapKit plein écran ; en haut, une seule rangée en verre (rayon visible et filtres par sorte) ;
// en bas, pastille « Autour de … », boussole et recentrage, puis explication de la position, carrousel des
// lieux (synchronisé avec l'épingle choisie, la caméra glisse vers le lieu), rayon vide ou erreur.
//
// T-172 (FB-11) : ouverture toujours sur Montréal (quartier du ménage, groupe, sinon centre-ville). Le bouton
// « position » de MapKit est remplacé par un recentrage sur l'origine : un simulateur à San Francisco n'emmène
// plus la carte hors de Montréal.
//
// R-015 : plus de rayons prédéfinis. La famille zoome et dézoome librement ; chaque mouvement de carte
// (`onMapCameraChange`) donne la zone visible au ViewModel, qui en tire le rayon et refiltre après un court délai.

import MapKit
import SwiftUI

struct FamilyMapScreen: View {
    @Environment(\.appContext) private var context
    @State private var viewModel: FamilyMapViewModel?
    @State private var location = FamilyLocationRequester()
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: FamilyMapViewModel.montrealCenter.location, latitudinalMeters: 12_000, longitudinalMeters: 12_000
    ))
    @State private var showsLocationDeniedAlert = false
    /// Dernière caméra de la carte, une fois le premier cadrage fait (recentrer en gardant le zoom, dézoomer).
    @State private var lastMapCamera: MapCamera?
    @State private var hasFittedCamera = false
    /// L'explication de la position a reçu une réponse (autoriser ou rester sur le quartier) : on ne la remontre plus.
    @AppStorage("familyMap.locationExplained") private var locationExplained = false

    /// Écran poussé depuis la carte (groupe, producteur ou lot). Poussé ici plutôt que par un
    /// `NavigationLink(value:)` : la carte est elle-même poussée par un lien à destination, et un lien à valeur
    /// la réinitialisait sans rien ouvrir.
    @State private var destination: FamilyMapDestination?

    @Namespace private var mapScope
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Hauteur de l'écran : plafonne la carte du lieu aux tailles d'accessibilité (T-182).
    @State private var screenHeight: CGFloat = 800

    var body: some View {
        ZStack {
            if let viewModel {
                FamilyMapCanvas(viewModel: viewModel, camera: $camera, destination: $destination, scope: mapScope,
                                reduceMotion: reduceMotion, onCameraChange: cameraChanged)
                    .ignoresSafeArea()
            } else {
                Color.fond.ignoresSafeArea()
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { screenHeight = $0 }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let viewModel { FamilyMapControlBar(viewModel: viewModel, reduceMotion: reduceMotion)
                    // Les pastilles flottent sur la carte : au-delà de ce plafond elles mangeaient l'écran.
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let viewModel {
                bottomLayer(viewModel)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
        }
        .mapScope(mapScope)
        .navigationDestination(item: $destination) { destination in
            switch destination {
            case .group(let id): GroupDetailScreen(groupId: id)
            case .vendor(let id): PublicVendorScreen(vendorId: id)
            case .offer(let id): OfferDetailScreen(offerId: id)
            }
        }
        .navigationTitle("Carte du quartier")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .alert("Position désactivée", isPresented: $showsLocationDeniedAlert) {
            Button("Ouvrir les Réglages") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Rester sur mon quartier", role: .cancel) {}
        } message: {
            Text("Autorise la position « pendant l'utilisation » dans les Réglages pour centrer la carte sur toi.")
        }
        .task {
            guard viewModel == nil else { return }
            let model = FamilyMapViewModel(repositories: context.repositories, householdId: context.householdId,
                                           userId: context.userId)
            viewModel = model
            await model.load()
            if location.authorization == .authorized { await locateFamily() }
        }
        .onChange(of: viewModel?.origin) { _, _ in fitCamera() }
        // Carrousel défilé ou épingle touchée : la caméra glisse vers le lieu, en gardant le zoom.
        .onChange(of: viewModel?.selectedPlaceID) { _, _ in flyToSelectedPlace() }
        .onChange(of: scenePhase) { _, phase in
            // Retour des Réglages : la position vient peut-être d'être autorisée.
            guard phase == .active else { return }
            let before = location.authorization
            location.refreshAuthorization()
            if before != .authorized, location.authorization == .authorized { Task { await locateFamily() } }
        }
    }

    // MARK: Couche du bas

    @ViewBuilder
    private func bottomLayer(_ viewModel: FamilyMapViewModel) -> some View {
        VStack(spacing: 12) {
            GlassEffectContainer(spacing: 12) {
                if dynamicTypeSize.isAccessibilitySize {
                    // T-182 : la pastille prend toute la largeur pour passer à la ligne ; boussole et recentrage
                    // montent au-dessus, côte à côte.
                    VStack(alignment: .trailing, spacing: 10) {
                        HStack(spacing: 10) {
                            MapCompass(scope: mapScope)
                            recenterButton(viewModel)
                        }
                        originPill(viewModel)
                    }
                } else {
                    HStack(alignment: .bottom, spacing: 12) {
                        originPill(viewModel)
                        Spacer(minLength: 0)
                        VStack(spacing: 10) {
                            MapCompass(scope: mapScope)
                            recenterButton(viewModel)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)

            Group {
                if needsLocationExplanation {
                    FamilyMapLocationExplainer(
                        neighborhood: viewModel.origin?.title,
                        onAllow: {
                            locationExplained = true
                            Task { await locateFamily() }
                        },
                        onDecline: { locationExplained = true }
                    )
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if !viewModel.places.isEmpty {
                    FamilyMapCarousel(
                        places: viewModel.places,
                        selectedID: Binding(
                            get: { viewModel.selectedPlaceID },
                            set: { id in withAnimation(reduceMotion ? nil : .smooth) { viewModel.selectedPlaceID = id } }
                        ),
                        reduceMotion: reduceMotion,
                        maxTileHeight: dynamicTypeSize.isAccessibilitySize ? max(screenHeight * 0.3, 180) : nil,
                        onOpen: { destination = $0 }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if case .empty = viewModel.state {
                    FamilyMapEmptyHint(zoomOut: zoomOut)
                        .padding(.horizontal, 16)
                        .transition(.opacity)
                } else if let error = viewModel.state.error {
                    FamilyMapErrorCard(error: error) { await viewModel.load() }
                        .padding(.horizontal, 16)
                        .transition(.opacity)
                }
            }
        }
        .padding(.bottom, 8)
        .animation(reduceMotion ? nil : .smooth, value: viewModel.places.isEmpty)
        .animation(reduceMotion ? nil : .smooth, value: needsLocationExplanation)
    }

    private func originPill(_ viewModel: FamilyMapViewModel) -> some View {
        FamilyMapOriginPill(viewModel: viewModel, authorization: location.authorization,
                            isLocating: location.isLocating, action: originTapped)
    }

    private func recenterButton(_ viewModel: FamilyMapViewModel) -> some View {
        Button("Recentrer la carte", systemImage: "scope", action: recenter)
            .labelStyle(.iconOnly)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.grenier)
            .frame(width: 48, height: 48)
            .contentShape(.circle)
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            // Icône dans un rond de 48 pt : au-delà de XXXL, elle débordait sur la pastille (T-182).
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityHint(viewModel.origin?.title ?? "")
    }

    private var needsLocationExplanation: Bool {
        location.authorization == .notDetermined && !locationExplained && !location.isLocating
    }

    // MARK: Position

    private func originTapped() {
        switch location.authorization {
        case .denied:
            showsLocationDeniedAlert = true
        case .notDetermined, .authorized:
            locationExplained = true
            Task { await locateFamily() }
        }
    }

    /// Demande la position (avec la feuille système si besoin) et recentre ; sinon reste sur le quartier.
    /// T-172 : une position loin de Montréal (simulateur) est ignorée sans message.
    private func locateFamily() async {
        guard let viewModel else { return }
        guard let coordinate = await location.currentLocation() else {
            viewModel.useHouseholdOrigin()
            return
        }
        withAnimation(reduceMotion ? nil : .smooth) {
            if !viewModel.useUserLocation(Geohash.Coordinate(coordinate)) { viewModel.useHouseholdOrigin() }
        }
    }

    /// Centre la carte sur l'origine : au premier cadrage avec le rayon initial, ensuite en gardant le zoom choisi.
    private func fitCamera(resetZoom: Bool = false) {
        guard let viewModel, let origin = viewModel.origin else { return }
        let center = origin.coordinate.location
        let target: MapCameraPosition
        if hasFittedCamera, !resetZoom, let last = lastMapCamera {
            target = .camera(MapCamera(centerCoordinate: center, distance: last.distance,
                                       heading: last.heading, pitch: last.pitch))
        } else {
            // MapKit étire la région carrée à la hauteur de l'écran : ce côté donne le rayon voulu au coin sur un iPhone.
            let side = viewModel.initialRadiusMeters * 0.85
            target = .region(MKCoordinateRegion(center: center, latitudinalMeters: side, longitudinalMeters: side))
        }
        hasFittedCamera = true
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.8)) { camera = target }
    }

    /// Bouton de recentrage : retour à l'origine (position ou quartier) au zoom de départ, sans lieu choisi.
    private func recenter() {
        viewModel?.selectedPlaceID = nil
        fitCamera(resetZoom: true)
    }

    /// Glisse vers le lieu choisi en gardant le zoom (et l'orientation) de la famille.
    private func flyToSelectedPlace() {
        guard let place = viewModel?.selectedPlace, let last = lastMapCamera else { return }
        let target = MapCamera(centerCoordinate: place.coordinate.location, distance: last.distance,
                               heading: last.heading, pitch: last.pitch)
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.6)) { camera = .camera(target) }
    }

    /// Chaque mouvement de carte (pincement, déplacement, boutons) donne la zone visible au ViewModel.
    private func cameraChanged(_ context: MapCameraUpdateContext) {
        // Avant le premier cadrage, la carte montre tout Montréal : ce n'est pas un choix de la famille.
        guard hasFittedCamera, let viewModel else { return }
        lastMapCamera = context.camera
        let region = context.region
        viewModel.visibleRegionChanged(center: Geohash.Coordinate(region.center),
                                       latitudeDelta: region.span.latitudeDelta,
                                       longitudeDelta: region.span.longitudeDelta)
    }

    /// « Dézoomer » de l'état vide : double la distance de la caméra.
    private func zoomOut() {
        guard let viewModel else { return }
        let target: MapCameraPosition
        if let last = lastMapCamera {
            target = .camera(MapCamera(centerCoordinate: last.centerCoordinate, distance: last.distance * 2,
                                       heading: last.heading, pitch: last.pitch))
        } else if let center = viewModel.searchArea?.center {
            let side = viewModel.displayedRadiusMeters * 2 * 2.0.squareRoot()
            target = .region(MKCoordinateRegion(center: center.location, latitudinalMeters: side, longitudinalMeters: side))
        } else {
            return
        }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.6)) { camera = target }
    }
}

// MARK: - Carte

private struct FamilyMapCanvas: View {
    @Bindable var viewModel: FamilyMapViewModel
    @Binding var camera: MapCameraPosition
    @Binding var destination: FamilyMapDestination?
    let scope: Namespace.ID
    let reduceMotion: Bool
    let onCameraChange: (MapCameraUpdateContext) -> Void

    /// Groupe d'épingles touché : sa feuille liste les lieux (T-176).
    @State private var openCluster: MapCluster<FamilyMapViewModel.Place>?
    /// Lieu choisi dans la feuille, sélectionné une fois la feuille fermée (un producteur pousse sa page).
    @State private var pendingPick: FamilyMapViewModel.Place?
    @State private var mapSize: CGSize = .zero
    @State private var lastSpan: MKCoordinateSpan?
    @ScaledMetric(relativeTo: .body) private var pinDiameter: CGFloat = 40

    var body: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom, .rotate], scope: scope) {
            if let origin = viewModel.origin {
                if origin.isUserLocation {
                    // T-172 : seulement quand la position est retenue (près de Montréal).
                    UserAnnotation()
                } else {
                    Annotation(origin.title, coordinate: origin.coordinate.location, anchor: .center) {
                        FamilyMapHomeMarker()
                    }
                    .annotationTitles(.hidden)
                }
            }

            ForEach(viewModel.annotations) { cluster in
                if cluster.isSingle, let place = cluster.members.first {
                    Annotation(place.name, coordinate: place.coordinate.location, anchor: .bottom) {
                        FamilyMapPin(kind: place.kind, photoURL: place.photoURL, name: place.name,
                                     isSelected: place.id == viewModel.selectedPlaceID,
                                     reduceMotion: reduceMotion) {
                            select(place)
                        }
                        .accessibilityLabel(place.accessibilityLabel)
                        .accessibilityHint(place.kind == .producer ? "Ouvre la page du producteur" : "Affiche les détails")
                        .accessibilityAddTraits(place.id == viewModel.selectedPlaceID ? [.isButton, .isSelected] : .isButton)
                    }
                    .annotationTitles(.hidden)
                } else {
                    // T-176 : plusieurs lieux au même endroit (ou trop proches à ce zoom) → une épingle pile.
                    Annotation(FamilyMapClusterText.title(count: cluster.count), coordinate: cluster.coordinate.location,
                               anchor: .bottom) {
                        FamilyMapClusterPin(kinds: cluster.members.map(\.kind),
                                            isSelected: cluster.contains(id: viewModel.selectedPlaceID),
                                            reduceMotion: reduceMotion) {
                            openCluster = cluster
                        }
                        .accessibilityLabel(FamilyMapClusterText.accessibilityLabel(for: cluster.members))
                        .accessibilityHint("Affiche la liste pour choisir un lieu")
                        .accessibilityAddTraits(cluster.contains(id: viewModel.selectedPlaceID) ? [.isButton, .isSelected] : .isButton)
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {}
        // Continu : la pastille du rayon suit le doigt ; le ViewModel diffère le filtrage.
        .onMapCameraChange(frequency: .continuous) { context in
            onCameraChange(context)
            updateClusterViewport(context.region.span)
        }
        .onGeometryChange(for: CGSize.self, of: \.size) { size in
            mapSize = size
            if let span = lastSpan { updateClusterViewport(span) }
        }
        .onChange(of: pinDiameter, initial: true) { _, diameter in
            // Diamètre de l'épingle + son contour + un peu d'air : au-dessous, elles se chevauchent.
            viewModel.pinSpacing = Double(min(diameter, 60)) + 12
        }
        .sheet(item: $openCluster, onDismiss: performPendingPick) { cluster in
            FamilyMapClusterSheet(
                places: cluster.members,
                selectedPlaceID: viewModel.selectedPlaceID,
                canZoom: MapClustering.zoomRegion(for: cluster.members.map(\.coordinate)) != nil,
                onPick: { place in
                    pendingPick = place
                    openCluster = nil
                },
                onZoom: {
                    openCluster = nil
                    zoom(into: cluster)
                }
            )
        }
        .overlay {
            if viewModel.state.isLoading || viewModel.origin == nil, viewModel.state.error == nil {
                FamilyMapLoadingBadge().transition(.opacity)
            }
        }
        .sensoryFeedback(.selection, trigger: viewModel.selectedPlaceID) { _, new in new != nil }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Carte des lieux autour de chez toi")
    }
}

extension FamilyMapCanvas {
    /// Toucher un lieu (épingle ou ligne de la feuille) : un producteur ouvre sa page (T-157), les autres
    /// affichent leur carte en bas (un second toucher la ferme).
    fileprivate func select(_ place: FamilyMapViewModel.Place) {
        if case .producer(let vendor, _, _) = place.detail {
            viewModel.selectedPlaceID = place.id
            destination = .vendor(vendor.id)
            return
        }
        withAnimation(reduceMotion ? nil : .smooth) {
            viewModel.selectedPlaceID = viewModel.selectedPlaceID == place.id ? nil : place.id
        }
    }

    fileprivate func performPendingPick() {
        guard let place = pendingPick else { return }
        pendingPick = nil
        // Depuis la feuille, on choisit toujours : pas de bascule qui désélectionnerait le lieu déjà choisi.
        if place.kind != .producer, viewModel.selectedPlaceID == place.id { return }
        select(place)
    }

    fileprivate func updateClusterViewport(_ span: MKCoordinateSpan) {
        lastSpan = span
        viewModel.mapViewportChanged(MapClustering.Viewport(
            latitudeDelta: span.latitudeDelta, longitudeDelta: span.longitudeDelta,
            width: Double(mapSize.width), height: Double(mapSize.height)))
    }

    /// « Zoomer ici » : cadre les lieux du groupe pour que leurs épingles se séparent.
    fileprivate func zoom(into cluster: MapCluster<FamilyMapViewModel.Place>) {
        guard let region = MapClustering.zoomRegion(for: cluster.members.map(\.coordinate)) else { return }
        let target = MKCoordinateRegion(
            center: region.center.location,
            span: MKCoordinateSpan(latitudeDelta: region.latitudeDelta, longitudeDelta: region.longitudeDelta))
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.6)) { camera = .region(target) }
    }
}

private struct FamilyMapLoadingBadge: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Chargement des lieux…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.texte)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Barre du haut (rayon visible et filtres)

/// T-172 : une seule rangée en verre, comme Plans : pastille du rayon puis filtres par sorte.
private struct FamilyMapControlBar: View {
    @Bindable var viewModel: FamilyMapViewModel
    let reduceMotion: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                // T-182 : à AX1–AX5, trois puces ne tiennent pas sur une rangée et cachaient la moitié de la carte :
                // le rayon reste, les filtres se replient dans un menu.
                HStack(spacing: 8) {
                    FamilyMapRadiusPill(viewModel: viewModel, reduceMotion: reduceMotion)
                        .fixedSize()
                    InfoButton(topic: .mapRadius).glassEffect(.regular.interactive(), in: .circle)
                    Spacer(minLength: 0)
                    FamilyMapKindMenu(viewModel: viewModel, reduceMotion: reduceMotion)
                }
                .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        FamilyMapRadiusPill(viewModel: viewModel, reduceMotion: reduceMotion)
                        InfoButton(topic: .mapRadius).glassEffect(.regular.interactive(), in: .circle)
                        ForEach(FamilyMapViewModel.Kind.allCases) { kind in
                            FamilyMapKindChip(
                                kind: kind,
                                count: viewModel.countsInRadius[kind] ?? 0,
                                isOn: viewModel.visibleKinds.contains(kind),
                                reduceMotion: reduceMotion
                            ) {
                                withAnimation(reduceMotion ? nil : .smooth) { viewModel.toggle(kind) }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }
        // Surcouche de carte : comme dans Plans, le texte s'arrête à AX3 pour laisser voir la carte.
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .sensoryFeedback(.selection, trigger: viewModel.visibleKinds)
    }
}

/// « 4,2 km » : suit le zoom de la carte (R-015). Pas un bouton : on change le rayon en zoomant.
private struct FamilyMapRadiusPill: View {
    let viewModel: FamilyMapViewModel
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "scope")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .symbolEffect(.pulse, isActive: !reduceMotion && viewModel.liveRadiusMeters != nil)
            Text(FamilyMapViewModel.radiusText(meters: viewModel.displayedRadiusMeters))
                .monospacedDigit()
                .foregroundStyle(Color.texte)
                .contentTransition(reduceMotion ? .identity : .numericText(value: viewModel.displayedRadiusMeters))
                .animation(reduceMotion ? nil : .snappy, value: viewModel.displayedRadiusMeters)
        }
        .font(.subheadline.weight(.bold))
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.radiusTitle)
        .accessibilityHint("Pince la carte pour zoomer ou dézoomer et changer le rayon")
    }
}

private struct FamilyMapKindChip: View {
    let kind: FamilyMapViewModel.Kind
    let count: Int
    let isOn: Bool
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: kind.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.bounce, value: reduceMotion ? false : isOn)
                Text(kind.pluralTitle)
                Text(count, format: .number)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(count)))
                    .padding(.horizontal, 6)
                    .background(isOn ? Color.onAccent.opacity(0.25) : kind.color.opacity(0.15), in: .capsule)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isOn ? Color.onAccent : Color.texte)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(isOn ? .regular.tint(kind.color).interactive() : .regular.interactive(), in: .capsule)
        .animation(reduceMotion ? nil : .smooth, value: count)
        .accessibilityLabel("\(kind.pluralTitle), \(count)")
        .accessibilityValue(isOn ? String(localized: "affichés") : String(localized: "masqués"))
        .accessibilityHint(isOn ? String(localized: "Masque ces lieux") : String(localized: "Affiche ces lieux"))
    }
}

/// T-182 : filtres par sorte repliés en menu aux tailles d'accessibilité. Le libellé montre combien de sortes
/// sont affichées ; le menu (texte système, sans plafond) liste chaque sorte avec son nombre de lieux.
private struct FamilyMapKindMenu: View {
    @Bindable var viewModel: FamilyMapViewModel
    let reduceMotion: Bool

    private var shownCount: Int { viewModel.visibleKinds.count }
    private var allShown: Bool { shownCount == FamilyMapViewModel.Kind.allCases.count }

    var body: some View {
        Menu {
            ForEach(FamilyMapViewModel.Kind.allCases) { kind in
                Toggle(isOn: Binding(
                    get: { viewModel.visibleKinds.contains(kind) },
                    set: { _ in withAnimation(reduceMotion ? nil : .smooth) { viewModel.toggle(kind) } }
                )) {
                    Label("\(kind.pluralTitle) (\(viewModel.countsInRadius[kind] ?? 0))", systemImage: kind.systemImage)
                }
            }
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    filterSymbol
                    Text("\(shownCount)/\(FamilyMapViewModel.Kind.allCases.count)")
                        .monospacedDigit()
                        .foregroundStyle(Color.texte)
                        .contentTransition(.numericText(value: Double(shownCount)))
                }
                filterSymbol
            }
            .font(.subheadline.weight(.bold))
            .padding(.horizontal, 14)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.capsule)
        }
        .menuActionDismissBehavior(.disabled)
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .animation(reduceMotion ? nil : .smooth, value: shownCount)
        .accessibilityLabel("Sortes de lieux")
        .accessibilityValue(String(localized: "\(shownCount) sur \(FamilyMapViewModel.Kind.allCases.count) affichées"))
        .accessibilityHint("Choisis les sortes de lieux à afficher")
    }

    private var filterSymbol: some View {
        Image(systemName: allShown ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.grenier)
            .contentTransition(.symbolEffect(.replace))
    }
}

// MARK: - Pastille « Autour de … »

private struct FamilyMapOriginPill: View {
    let viewModel: FamilyMapViewModel
    let authorization: FamilyLocationRequester.Authorization
    let isLocating: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var isLarge: Bool { dynamicTypeSize.isAccessibilitySize }
    /// Capsule (moitié de 48 pt) sur une ligne ; mêmes coins quand le texte passe à la ligne.
    private var cornerRadius: CGFloat { 24 }

    private var symbol: String {
        if viewModel.origin?.isUserLocation == true { return "location.fill" }
        return authorization == .denied ? "location.slash.fill" : "house.fill"
    }

    private var subtitle: String {
        if isLocating { return String(localized: "Recherche de ta position…") }
        return viewModel.summaryText
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: isLarge ? .firstTextBaseline : .center, spacing: 10) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.grenier)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.pulse, isActive: isLocating)
                    .frame(minWidth: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(viewModel.origin?.title ?? String(localized: "Ton quartier"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.texte)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.texteSecondaire)
                        .contentTransition(.numericText())
                }
                .lineLimit(isLarge ? nil : 2)
                .fixedSize(horizontal: false, vertical: isLarge)
                .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, isLarge ? 12 : 8)
            .frame(minHeight: 48)
            .frame(maxWidth: isLarge ? .infinity : nil, alignment: .leading)
            .contentShape(.rect(cornerRadius: cornerRadius))
        }
        .buttonStyle(.plain)
        // T-182 : en capsule, un texte sur plusieurs lignes donnait un grand cercle. Aux tailles d'accessibilité, la
        // pastille prend la largeur et garde des coins de capsule (24 pt) sans s'arrondir en rond.
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityHint(viewModel.origin?.isUserLocation == true
                           ? String(localized: "Recentre la carte sur ta position")
                           : String(localized: "Centre la carte sur ta position"))
    }
}

// MARK: - États du bas

private struct FamilyMapEmptyHint: View {
    let zoomOut: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "map")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Rien dans ce coin")
                    .font(.headline)
                    .foregroundStyle(Color.texte)
                Text("Dézoome la carte ou affiche d'autres sortes de lieux.")
                    .font(.subheadline)
                    .foregroundStyle(Color.texteSecondaire)
            }
            Spacer(minLength: 0)
            Button("Dézoomer", systemImage: "minus.magnifyingglass", action: zoomOut)
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(.glass)
                .tint(.grenier)
                .accessibilityLabel("Dézoomer la carte")
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}

private struct FamilyMapErrorCard: View {
    let error: AppError
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(error.title).font(.headline).foregroundStyle(Color.texte)
                    Text(error.message).font(.subheadline).foregroundStyle(Color.texteSecondaire)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.grenier)
            }
            Button {
                Task { await retry() }
            } label: {
                Label("Réessayer", systemImage: "arrow.clockwise")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .tint(.grenier)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .sensoryFeedback(.error, trigger: error.message)
    }
}

/// Écran ouvert depuis la carte : la fiche d'un lieu ou le pin d'un producteur.
enum FamilyMapDestination: Hashable {
    case group(String)
    case vendor(String)
    case offer(String)
}

// MARK: - Montréal et coordonnées

extension Geohash.Coordinate {
    /// Pour MapKit.
    var location: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

// MARK: - Previews

#if DEBUG
#Preview("Clair") {
    NavigationStack {
        FamilyMapScreen()
            .navigationDestination(for: GroupRoute.self) { GroupDetailScreen(groupId: $0.groupId) }
            .offerDestination()
    }
    .environment(\.appContext, .instant)
}

#Preview("Sombre") {
    NavigationStack {
        FamilyMapScreen()
    }
    .environment(\.appContext, .instant)
    .preferredColorScheme(.dark)
}

#Preview("AX5") {
    NavigationStack {
        FamilyMapScreen()
    }
    .environment(\.appContext, .instant)
    .dynamicTypeSize(.accessibility5)
}

#Preview("Erreur") {
    NavigationStack {
        FamilyMapScreen()
    }
    .environment(\.appContext, AppContext(
        repositories: .fake(behavior: .failing(.offline)), userId: FakeData.ID.amina,
        householdId: FakeData.ID.aminaHousehold, groupId: nil, vendorId: FakeData.ID.fermeRive
    ))
}
#endif
