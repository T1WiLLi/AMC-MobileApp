// FamilyMapScreen.swift
// Carte pour les familles (T-091, spec S-02) : groupes, points de cueillette et producteurs autour de chez soi.
// Poussée depuis l'onglet Groupes (bouton carte de la barre d'outils) : les routes `GroupRoute` et `OfferRoute`
// sont celles du NavigationStack de l'onglet.
//
// Couches : carte MapKit plein écran ; en haut, barre en verre (pastille « Dans un rayon de 4,2 km » et filtres
// par sorte) ; en bas, pastille « Autour de … », contrôles de carte, puis explication de la position, carte du
// lieu touché, rayon vide ou erreur.
//
// R-015 : plus de rayons prédéfinis. La famille zoome et dézoome librement ; chaque mouvement de carte
// (`onMapCameraChange`) donne la zone visible au ViewModel, qui en tire le rayon et refiltre après un court délai.

import MapKit
import SwiftUI

struct FamilyMapScreen: View {
    @Environment(\.appContext) private var context
    @State private var viewModel: FamilyMapViewModel?
    @State private var location = FamilyLocationRequester()
    @State private var camera: MapCameraPosition = .region(.montreal)
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
        .safeAreaInset(edge: .top, spacing: 0) {
            if let viewModel { FamilyMapControlBar(viewModel: viewModel, reduceMotion: reduceMotion) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let viewModel { bottomLayer(viewModel) }
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
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                HStack(alignment: .bottom, spacing: 12) {
                    FamilyMapOriginPill(viewModel: viewModel, authorization: location.authorization,
                                        isLocating: location.isLocating, action: originTapped)
                    Spacer(minLength: 0)
                    VStack(spacing: 10) {
                        MapCompass(scope: mapScope)
                        MapUserLocationButton(scope: mapScope)
                    }
                    .buttonBorderShape(.circle)
                }

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
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if let place = viewModel.selectedPlace {
                        FamilyMapPlaceCard(place: place, onOpen: { destination = $0 }) {
                            withAnimation(reduceMotion ? nil : .smooth) { viewModel.selectedPlaceID = nil }
                        }
                        .id(place.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if case .empty = viewModel.state {
                        FamilyMapEmptyHint(zoomOut: zoomOut)
                            .transition(.opacity)
                    } else if let error = viewModel.state.error {
                        FamilyMapErrorCard(error: error) { await viewModel.load() }
                            .transition(.opacity)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(reduceMotion ? nil : .smooth, value: viewModel.selectedPlace?.id)
        .animation(reduceMotion ? nil : .smooth, value: needsLocationExplanation)
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
    private func locateFamily() async {
        guard let viewModel else { return }
        guard let coordinate = await location.currentLocation() else {
            viewModel.useHouseholdOrigin()
            return
        }
        withAnimation(reduceMotion ? nil : .smooth) {
            _ = viewModel.useUserLocation(Geohash.Coordinate(coordinate))
        }
    }

    /// Centre la carte sur l'origine : au premier cadrage avec le rayon par défaut, ensuite en gardant le zoom choisi.
    private func fitCamera() {
        guard let viewModel, let origin = viewModel.origin else { return }
        let center = origin.coordinate.location
        let target: MapCameraPosition
        if hasFittedCamera, let last = lastMapCamera {
            target = .camera(MapCamera(centerCoordinate: center, distance: last.distance,
                                       heading: last.heading, pitch: last.pitch))
        } else {
            // MapKit étire la région carrée à la hauteur de l'écran : ce côté donne ≈ 1,5 km au coin sur un iPhone.
            let side = FamilyMapViewModel.defaultRadiusMeters * 0.85
            target = .region(MKCoordinateRegion(center: center, latitudinalMeters: side, longitudinalMeters: side))
        }
        hasFittedCamera = true
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.7)) { camera = target }
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

    var body: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom, .rotate], scope: scope) {
            UserAnnotation()

            if let origin = viewModel.origin {
                if !origin.isUserLocation {
                    Annotation(origin.title, coordinate: origin.coordinate.location, anchor: .center) {
                        FamilyMapHomeMarker()
                    }
                    .annotationTitles(.hidden)
                }
            }

            ForEach(viewModel.places) { place in
                Annotation(place.name, coordinate: place.coordinate.location, anchor: .bottom) {
                    FamilyMapPin(kind: place.kind, isSelected: place.id == viewModel.selectedPlaceID,
                                 reduceMotion: reduceMotion) {
                        // T-157 : un producteur ouvre directement sa page (la fiche reste sélectionnée au retour).
                        if case .producer(let vendor, _, _) = place.detail {
                            viewModel.selectedPlaceID = place.id
                            destination = .vendor(vendor.id)
                            return
                        }
                        withAnimation(reduceMotion ? nil : .smooth) {
                            viewModel.selectedPlaceID = viewModel.selectedPlaceID == place.id ? nil : place.id
                        }
                    }
                    .accessibilityLabel(place.accessibilityLabel)
                    .accessibilityHint(place.kind == .producer ? "Ouvre la page du producteur" : "Affiche les détails")
                    .accessibilityAddTraits(place.id == viewModel.selectedPlaceID ? [.isButton, .isSelected] : .isButton)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {}
        // Continu : la pastille du rayon suit le doigt ; le ViewModel diffère le filtrage.
        .onMapCameraChange(frequency: .continuous) { context in onCameraChange(context) }
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

private struct FamilyMapControlBar: View {
    @Bindable var viewModel: FamilyMapViewModel
    let reduceMotion: Bool

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                FamilyMapRadiusPill(viewModel: viewModel, reduceMotion: reduceMotion)

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
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
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .sensoryFeedback(.selection, trigger: viewModel.visibleKinds)
    }
}

/// « Dans un rayon de 4,2 km » : suit le zoom de la carte (R-015). Pas un bouton : on change le rayon en zoomant.
private struct FamilyMapRadiusPill: View {
    let viewModel: FamilyMapViewModel
    let reduceMotion: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Tailles d'accessibilité : seul le rayon reste, pour ne pas cacher la carte (l'indice passe par VoiceOver).
    private var isCompact: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        HStack(spacing: 12) {
            if !isCompact { icon }
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.radiusTitle)
                    .font(.headline)
                    .foregroundStyle(Color.texte)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText(value: viewModel.displayedRadiusMeters))
                    .animation(reduceMotion ? nil : .snappy, value: viewModel.displayedRadiusMeters)
                if !isCompact {
                    Label("Pince la carte pour zoomer ou dézoomer", systemImage: "hand.pinch")
                        .font(.caption)
                        .foregroundStyle(Color.texteSecondaire)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        // Surcouche de carte : comme dans Plans, le texte s'arrête à AX3 pour laisser voir la carte.
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.radiusTitle)
        .accessibilityHint("Zoome ou dézoome la carte pour changer le rayon")
    }

    private var icon: some View {
        Image(systemName: "scope")
            .font(.title3.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.grenier)
            .symbolEffect(.pulse, isActive: !reduceMotion && viewModel.liveRadiusMeters != nil)
            .accessibilityHidden(true)
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

// MARK: - Pastille « Autour de … »

private struct FamilyMapOriginPill: View {
    let viewModel: FamilyMapViewModel
    let authorization: FamilyLocationRequester.Authorization
    let isLocating: Bool
    let action: () -> Void

    private var symbol: String {
        if viewModel.origin?.isUserLocation == true { return "location.fill" }
        return authorization == .denied ? "location.slash.fill" : "house.fill"
    }

    private var subtitle: String {
        if isLocating { return String(localized: "Recherche de ta position…") }
        if viewModel.isUserLocationOutOfArea { return String(localized: "Tu sembles loin : carte sur ton quartier") }
        return viewModel.summaryText
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.grenier)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.pulse, isActive: isLocating)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(viewModel.origin?.title ?? String(localized: "Ton quartier"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.texte)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.texteSecondaire)
                        .contentTransition(.numericText())
                }
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 48)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
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
