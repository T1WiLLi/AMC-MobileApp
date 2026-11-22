// FamilyMapViewModel.swift
// Carte pour les familles (T-091, spec S-02) : groupes, points de cueillette et producteurs autour de chez soi.
//
// Usage dans une vue :
//   @State private var model = FamilyMapViewModel(repositories: repos, householdId: id, userId: userId)
//   .task { await model.load() }                         // centre d'abord sur le quartier du ménage
//   model.useUserLocation(coordinate)                    // quand la position est autorisée
//   .onMapCameraChange(frequency: .continuous) { model.visibleRegionChanged(center:latitudeDelta:longitudeDelta:) }
//   Plus de rayons prédéfinis (R-015) : la zone visible fixe le rayon, `state` se recalcule (différé de `debounce`).
//   switch model.state { case .loaded(let places): Annotation par lieu, `place.distanceText` (« à 650 m ») }
//
// Positions : centre du groupe (geohash), `PickupPoint.geohash`, `Vendor.storefrontGeohash`. Un lieu sans
// position n'apparaît pas. Jamais d'adresse exacte : tout passe par des geohash tronqués.

import Foundation
import Observation

@Observable
@MainActor
final class FamilyMapViewModel {
    /// Les trois sortes de lieux de la carte.
    nonisolated enum Kind: String, CaseIterable, Identifiable, Sendable, Hashable {
        case group
        case pickupPoint
        case producer

        var id: String { rawValue }

        /// « Groupes », « Cueillettes », « Producteurs » (puces de filtre).
        var pluralTitle: String {
            switch self {
            case .group: String(localized: "Groupes")
            case .pickupPoint: String(localized: "Cueillettes")
            case .producer: String(localized: "Producteurs")
            }
        }

        /// « Groupe de quartier », « Point de cueillette », « Producteur » (carte du bas, VoiceOver).
        var title: String {
            switch self {
            case .group: String(localized: "Groupe de quartier")
            case .pickupPoint: String(localized: "Point de cueillette")
            case .producer: String(localized: "Producteur")
            }
        }

        var systemImage: String {
            switch self {
            case .group: "person.3.fill"
            case .pickupPoint: "shippingbox.fill"
            case .producer: "leaf.fill"
            }
        }
    }

    /// Zone de recherche : le cercle qui couvre la partie visible de la carte (R-015).
    nonisolated struct SearchArea: Sendable, Hashable {
        var center: Geohash.Coordinate
        var radiusMeters: Double

        init(center: Geohash.Coordinate, radiusMeters: Double) {
            self.center = center
            self.radiusMeters = FamilyMapViewModel.clampedRadius(radiusMeters)
        }

        /// « 4,2 km », « 850 m ».
        var radiusText: String { FamilyMapViewModel.radiusText(meters: radiusMeters) }
    }

    /// Centre de la carte : la position de la famille, ou à défaut le quartier du ménage.
    nonisolated enum Origin: Sendable, Hashable {
        /// Geohash approximatif du ménage ; `neighborhood` pour le libellé (« Saint-Michel »).
        case household(Geohash.Coordinate, neighborhood: String?)
        case userLocation(Geohash.Coordinate)

        var coordinate: Geohash.Coordinate {
            switch self {
            case .household(let coordinate, _), .userLocation(let coordinate): coordinate
            }
        }

        var isUserLocation: Bool {
            if case .userLocation = self { true } else { false }
        }

        /// « Autour de toi », « Autour de Saint-Michel », « Autour de ton quartier ».
        var title: String {
            switch self {
            case .userLocation: String(localized: "Autour de toi")
            case .household(_, let neighborhood?) where !neighborhood.isEmpty: String(localized: "Autour de \(neighborhood)")
            case .household: String(localized: "Autour de ton quartier")
            }
        }
    }

    /// Un lieu sur la carte.
    nonisolated struct Place: Identifiable, Sendable, Hashable {
        nonisolated enum Detail: Sendable, Hashable {
            case group(NeighborhoodGroup, isMember: Bool)
            case pickupPoint(PickupPoint)
            /// `offerId` : lot actif le plus proche de sa date limite, nil s'il n'en a aucun.
            case producer(Vendor, offerId: String?, openOfferCount: Int)
        }

        var detail: Detail
        var coordinate: Geohash.Coordinate
        /// Distance au centre de la carte, en mètres.
        var distanceMeters: Double = 0

        /// « group:group-saint-michel » : unique entre les sortes.
        var id: String { "\(kind.rawValue):\(sourceId)" }

        var kind: Kind {
            switch detail {
            case .group: .group
            case .pickupPoint: .pickupPoint
            case .producer: .producer
            }
        }

        var sourceId: String {
            switch detail {
            case .group(let group, _): group.id
            case .pickupPoint(let point): point.id
            case .producer(let vendor, _, _): vendor.id
            }
        }

        var name: String {
            switch detail {
            case .group(let group, _): group.name
            case .pickupPoint(let point): point.name
            case .producer(let vendor, _, _): vendor.legalName
            }
        }

        /// « à 650 m ».
        var distanceText: String { NearbyGroupsViewModel.distanceText(meters: distanceMeters) }

        /// « Groupe de quartier, Voisins de Saint-Michel, à 10 m ».
        var accessibilityLabel: String { "\(kind.title), \(name), \(distanceText)" }
    }

    // MARK: Filtres (le résultat se recalcule à chaque changement)

    /// Zone filtrée, posée par la carte (différée) ; nil → `defaultRadiusMeters` autour de `origin`.
    private(set) var visibleArea: SearchArea?
    /// Rayon affiché tout de suite pendant le geste (la liste suit après `debounce`).
    private(set) var liveRadiusMeters: Double?
    /// Sortes de lieux affichées ; toutes par défaut.
    var visibleKinds: Set<Kind> = Set(Kind.allCases)
    /// Lieu touché sur la carte (carte du bas) ; ignoré s'il sort du rayon ou du filtre.
    var selectedPlaceID: String?

    // MARK: État

    /// Tous les lieux localisables, sans filtre ni distance.
    private(set) var allPlaces: LoadState<[Place]> = .idle
    /// Centre de la carte ; nil avant le premier chargement.
    private(set) var origin: Origin?
    /// La position reçue était trop loin du quartier (hors de Montréal, simulateur) : on reste sur le quartier.
    private(set) var isUserLocationOutOfArea = false

    let householdId: String
    let userId: String?
    private let repositories: AppRepositories
    /// Quartier du ménage, gardé pour revenir dessus quand la position est refusée.
    private var householdOrigin: Origin?

    /// Au-delà de cette distance du quartier, la position de l'appareil est ignorée.
    nonisolated static let maxDistanceFromHomeMeters = 25_000.0
    /// Rayon avant que la carte ait donné sa zone visible (premier cadrage).
    nonisolated static let defaultRadiusMeters = 1_500.0
    /// Bornes du rayon : un zoom extrême ne vide pas la carte et un dézoom ne charge pas tout le Québec.
    nonisolated static let radiusRangeMeters = 200.0...50_000.0

    /// Délai entre la fin d'un mouvement de carte et le nouveau filtrage.
    let debounce: Duration
    private var pendingArea: Task<Void, Never>?

    init(repositories: AppRepositories, householdId: String, userId: String? = nil,
         debounce: Duration = .milliseconds(300)) {
        self.repositories = repositories
        self.householdId = householdId
        self.userId = userId
        self.debounce = debounce
    }

    /// Zone qui filtre les lieux : celle de la carte, sinon le rayon par défaut autour du centre.
    var searchArea: SearchArea? {
        if let visibleArea { return visibleArea }
        guard let origin else { return nil }
        return SearchArea(center: origin.coordinate, radiusMeters: Self.defaultRadiusMeters)
    }

    /// Rayon à afficher dans la pastille (suit le doigt, avant même le filtrage).
    var displayedRadiusMeters: Double {
        liveRadiusMeters ?? searchArea?.radiusMeters ?? Self.defaultRadiusMeters
    }

    /// « Dans un rayon de 4,2 km ».
    var radiusTitle: String {
        String(localized: "Dans un rayon de \(Self.radiusText(meters: displayedRadiusMeters))")
    }

    /// Lieux dans le rayon et le filtre, du plus proche au plus loin ; `.empty` s'il n'y en a aucun.
    var state: LoadState<[Place]> {
        switch allPlaces {
        case .idle: return .idle
        case .loading: return .loading
        case .empty: return .empty
        case .failed(let error): return .failed(error)
        case .loaded(let places):
            guard let origin, let area = searchArea else { return .loading }
            return .from(Self.filter(places, in: area, distanceFrom: origin.coordinate, kinds: visibleKinds))
        }
    }

    var places: [Place] { state.value ?? [] }

    /// Nombre de lieux de chaque sorte dans le rayon (sans le filtre de sorte), pour les puces.
    var countsInRadius: [Kind: Int] {
        guard let all = allPlaces.value, let origin, let area = searchArea else { return [:] }
        let inRadius = Self.filter(all, in: area, distanceFrom: origin.coordinate, kinds: Set(Kind.allCases))
        return Dictionary(grouping: inRadius, by: \.kind).mapValues(\.count)
    }

    /// Lieu sélectionné, s'il est encore visible.
    var selectedPlace: Place? {
        guard let selectedPlaceID else { return nil }
        return places.first { $0.id == selectedPlaceID }
    }

    /// « 8 lieux dans ce rayon », « Aucun lieu dans ce rayon » (le rayon est dans la pastille du haut).
    var summaryText: String {
        let count = places.count
        if count == 0 { return String(localized: "Aucun lieu dans ce rayon") }
        let noun = count > 1 ? "lieux" : "lieu"
        return String(localized: "\(count) \(noun) dans ce rayon")
    }

    // MARK: Actions

    /// Charge (ou recharge) les lieux et le quartier du ménage. Garde la carte affichée pendant un rechargement.
    func load() async {
        if allPlaces.value == nil { allPlaces = .loading }
        let repositories = repositories, householdId = householdId, userId = userId
        do {
            let household = try await repositories.users.household(id: householdId)
            async let userNeighborhood = Self.neighborhood(ofUser: userId, repositories: repositories)
            async let publicGroups = repositories.groups.groups(inNeighborhood: nil)
            async let myGroups = repositories.groups.groups(ofHousehold: householdId)
            async let pickupPoints = repositories.pickupPoints.pickupPoints()
            async let vendors = repositories.vendors.vendors()
            async let offers = repositories.offers.activeOffers(inZone: nil)

            let mine = try await myGroups
            let places = Self.places(
                groups: try await publicGroups + mine,
                memberOf: Set(mine.map(\.id)),
                pickupPoints: try await pickupPoints,
                vendors: try await vendors,
                offers: try await offers
            )
            guard let center = Geohash.center(of: household.geohash) else {
                throw AppError.invalidInput(String(localized: "La position du ménage est inconnue."))
            }
            let neighborhood = await userNeighborhood ?? mine.first?.neighborhood
            let home = Origin.household(center, neighborhood: neighborhood)
            householdOrigin = home
            if origin == nil || origin?.isUserLocation == false { origin = home }
            allPlaces = .from(places)
        } catch {
            if allPlaces.value == nil { allPlaces = .failed(AppError(error)) }
        }
    }

    /// Centre la carte sur la position de la famille. Ignorée (et signalée) si elle est loin du quartier.
    /// Renvoie vrai si la carte est maintenant centrée sur la position.
    @discardableResult
    func useUserLocation(_ coordinate: Geohash.Coordinate) -> Bool {
        if let home = householdOrigin,
           Geohash.distanceMeters(from: home.coordinate, to: coordinate) > Self.maxDistanceFromHomeMeters {
            isUserLocationOutOfArea = true
            return false
        }
        isUserLocationOutOfArea = false
        origin = .userLocation(coordinate)
        return true
    }

    /// La carte a bougé (pincement, déplacement, boutons) : le rayon affiché suit tout de suite,
    /// le filtrage suit `debounce` après le dernier mouvement.
    func visibleRegionChanged(center: Geohash.Coordinate, latitudeDelta: Double, longitudeDelta: Double) {
        let area = SearchArea(center: center, radiusMeters: Self.radiusMeters(
            center: center, latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta))
        liveRadiusMeters = area.radiusMeters
        pendingArea?.cancel()
        let delay = debounce
        pendingArea = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            self?.applyVisibleArea(area)
        }
    }

    /// Attend le filtrage en cours (tests).
    func settle() async { await pendingArea?.value }

    /// Pose la zone filtrée sans délai.
    func applyVisibleArea(_ area: SearchArea) {
        visibleArea = area
        liveRadiusMeters = nil
    }

    /// Revient sur le quartier du ménage (position refusée ou indisponible).
    func useHouseholdOrigin() {
        if let householdOrigin { origin = householdOrigin }
    }

    /// Affiche ou masque une sorte de lieu ; garde toujours au moins une sorte visible.
    func toggle(_ kind: Kind) {
        if visibleKinds.contains(kind) {
            guard visibleKinds.count > 1 else { return }
            visibleKinds.remove(kind)
        } else {
            visibleKinds.insert(kind)
        }
    }

    // MARK: Calculs (purs, testables)

    /// Lieux localisables : groupes (sans doublon), points de cueillette et producteurs avec une position.
    nonisolated static func places(
        groups: [NeighborhoodGroup], memberOf: Set<String>, pickupPoints: [PickupPoint],
        vendors: [Vendor], offers: [Offer]
    ) -> [Place] {
        var seenGroups = Set<String>()
        let groupPlaces = groups.compactMap { group -> Place? in
            guard seenGroups.insert(group.id).inserted, let center = Geohash.center(of: group.centerGeohash) else {
                return nil
            }
            return Place(detail: .group(group, isMember: memberOf.contains(group.id)), coordinate: center)
        }
        let pickupPlaces = pickupPoints.compactMap { point -> Place? in
            guard let geohash = point.geohash, let center = Geohash.center(of: geohash) else { return nil }
            return Place(detail: .pickupPoint(point), coordinate: center)
        }
        let offersByVendor = Dictionary(grouping: offers.filter { $0.status == .active }, by: \.vendorId)
        let producerPlaces = vendors.compactMap { vendor -> Place? in
            guard let geohash = vendor.storefrontGeohash, let center = Geohash.center(of: geohash) else { return nil }
            let vendorOffers = (offersByVendor[vendor.id] ?? []).sorted { $0.deadline < $1.deadline }
            return Place(detail: .producer(vendor, offerId: vendorOffers.first?.id, openOfferCount: vendorOffers.count),
                         coordinate: center)
        }
        return groupPlaces + pickupPlaces + producerPlaces
    }

    /// Lieux des sortes demandées dans `area` (bord inclus), avec leur distance à `origin` (la famille),
    /// du plus proche au plus loin puis par nom.
    nonisolated static func filter(
        _ places: [Place], in area: SearchArea, distanceFrom origin: Geohash.Coordinate, kinds: Set<Kind>
    ) -> [Place] {
        places
            .filter { kinds.contains($0.kind) }
            .filter { Geohash.distanceMeters(from: area.center, to: $0.coordinate) <= area.radiusMeters }
            .map { place in
                var place = place
                place.distanceMeters = Geohash.distanceMeters(from: origin, to: place.coordinate)
                return place
            }
            .sorted { ($0.distanceMeters, $0.name) < ($1.distanceMeters, $1.name) }
    }

    /// Rayon de la zone visible : du centre au coin de la région (demi-diagonale), pour que tout lieu
    /// visible à l'écran soit dans le filtre. Borné par `radiusRangeMeters`.
    nonisolated static func radiusMeters(center: Geohash.Coordinate, latitudeDelta: Double, longitudeDelta: Double) -> Double {
        let corner = Geohash.Coordinate(
            latitude: min(90, center.latitude + abs(latitudeDelta) / 2),
            longitude: center.longitude + abs(longitudeDelta) / 2
        )
        return clampedRadius(Geohash.distanceMeters(from: center, to: corner))
    }

    nonisolated static func clampedRadius(_ meters: Double) -> Double {
        guard meters.isFinite else { return radiusRangeMeters.upperBound }
        return min(max(meters, radiusRangeMeters.lowerBound), radiusRangeMeters.upperBound)
    }

    /// « 850 m » (à 50 m près), « 4,2 km » (au dixième), « 18 km » (au km dès 10 km).
    nonisolated static func radiusText(meters: Double) -> String {
        let meters = max(0, meters)
        if meters < 950 { return "\(max(50, Int((meters / 50).rounded()) * 50)) m" }
        let tenths = Int((meters / 100).rounded())
        if tenths < 100 {
            return tenths % 10 == 0 ? "\(tenths / 10) km" : "\(tenths / 10),\(tenths % 10) km"
        }
        return "\(Int((meters / 1_000).rounded())) km"
    }

    nonisolated private static func neighborhood(ofUser userId: String?, repositories: AppRepositories) async -> String? {
        guard let userId, let raw = try? await repositories.users.user(id: userId).neighborhood else { return nil }
        return displayName(ofNeighborhood: raw)
    }

    /// « parc-extension » (slug du seed) → « Parc-Extension » ; un nom déjà mis en forme reste tel quel.
    nonisolated static func displayName(ofNeighborhood raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed == trimmed.lowercased() else { return trimmed }
        let particles: Set<String> = ["de", "des", "du", "la", "le", "les"]
        return trimmed.split(separator: "-").enumerated().map { index, word in
            index > 0 && particles.contains(String(word)) ? String(word) : word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: "-")
    }
}
