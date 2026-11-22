import Foundation
import Testing
@testable import AMC_MobileApp

/// T-091 + R-015 : carte des familles, filtre par la zone visible (rayon libre qui suit le zoom), par sorte
/// de lieu et centre de la carte.
/// Amina habite en f25dv (Saint-Michel). Autour : le groupe Saint-Michel (centre), trois points de cueillette
/// (≈ 235 m à 1,8 km) et quatre producteurs (≈ 535 m à 1,9 km). Hochelaga (≈ 4,9 km) n'est pas à moins de 2 km.
@MainActor
struct FamilyMapViewModelTests {
    private typealias ID = FakeData.ID
    private typealias Kind = FamilyMapViewModel.Kind
    private typealias Area = FamilyMapViewModel.SearchArea

    private func viewModel(
        data: FakeData = .montreal, behavior: FakeBehavior = .instant, debounce: Duration = .zero
    ) -> FamilyMapViewModel {
        FamilyMapViewModel(repositories: .fake(behavior: behavior, data: data), householdId: ID.aminaHousehold,
                           userId: ID.amina, debounce: debounce)
    }

    private func ids(_ model: FamilyMapViewModel) -> [String] { model.places.map(\.sourceId) }

    /// La carte montre un cercle de `meters` autour du centre (comme après un pincement).
    private func zoom(_ model: FamilyMapViewModel, to meters: Double) throws {
        let center = try #require(model.origin?.coordinate)
        model.applyVisibleArea(Area(center: center, radiusMeters: meters))
    }

    private static let metersPerDegree = Geohash.earthRadiusMeters * .pi / 180

    // MARK: Zone visible → rayon

    @Test func regionRadiusIsTheHalfDiagonalOfTheVisibleRegion() {
        let center = Geohash.Coordinate(latitude: 45.55, longitude: -73.6)
        // Région carrée de 2 km de côté : demi-diagonale ≈ 1 414 m.
        let latDelta = 2_000 / Self.metersPerDegree
        let lonDelta = latDelta / cos(center.latitude * .pi / 180)
        let radius = FamilyMapViewModel.radiusMeters(center: center, latitudeDelta: latDelta, longitudeDelta: lonDelta)
        #expect(abs(radius - 1_414) < 10)

        // Zoomer (région deux fois plus petite) divise le rayon par deux.
        let zoomedIn = FamilyMapViewModel.radiusMeters(center: center, latitudeDelta: latDelta / 2, longitudeDelta: lonDelta / 2)
        #expect(abs(zoomedIn - radius / 2) < 5)

        // Le signe des écarts n'a pas d'importance.
        #expect(FamilyMapViewModel.radiusMeters(center: center, latitudeDelta: -latDelta, longitudeDelta: -lonDelta) == radius)
    }

    @Test func regionRadiusIsClamped() {
        let center = Geohash.Coordinate(latitude: 45.55, longitude: -73.6)
        // Zoom extrême : un pâté de maisons → 200 m minimum.
        #expect(FamilyMapViewModel.radiusMeters(center: center, latitudeDelta: 0.0001, longitudeDelta: 0.0001) == 200)
        // Dézoom sur tout le Québec → 50 km maximum.
        #expect(FamilyMapViewModel.radiusMeters(center: center, latitudeDelta: 20, longitudeDelta: 30) == 50_000)
        #expect(FamilyMapViewModel.clampedRadius(.infinity) == 50_000)
        #expect(FamilyMapViewModel.clampedRadius(.nan) == 50_000)
        #expect(Area(center: center, radiusMeters: 10).radiusMeters == 200)
    }

    @Test func radiusTextReadsNaturally() {
        #expect(FamilyMapViewModel.radiusText(meters: 200) == "200 m")
        #expect(FamilyMapViewModel.radiusText(meters: 862) == "850 m")
        #expect(FamilyMapViewModel.radiusText(meters: 1_000) == "1 km")
        #expect(FamilyMapViewModel.radiusText(meters: 1_500) == "1,5 km")
        #expect(FamilyMapViewModel.radiusText(meters: 4_230) == "4,2 km")
        #expect(FamilyMapViewModel.radiusText(meters: 9_960) == "10 km")
        #expect(FamilyMapViewModel.radiusText(meters: 18_400) == "18 km")
    }

    // MARK: Filtrage par la zone visible

    @Test func startsWithTheDefaultRadiusAroundTheNeighborhood() async throws {
        let model = viewModel()
        await model.load()
        #expect(model.visibleArea == nil)
        #expect(model.searchArea?.radiusMeters == 1_500)
        #expect(model.places.count == 6)
        #expect(model.places.allSatisfy { $0.distanceMeters <= 1_500 })
        #expect(model.radiusTitle == "Dans un rayon de 1,5 km")
        #expect(model.summaryText == "6 lieux dans ce rayon")
    }

    @Test func zoomingInShowsTheClosestPlacesByDistance() async throws {
        let model = viewModel()
        await model.load()
        try zoom(model, to: 1_000)
        #expect(ids(model) == [ID.saintMichel, ID.jarryPickup, ID.fournil, ID.pieIXPickup])
        #expect(model.places.map(\.kind) == [.group, .pickupPoint, .producer, .pickupPoint])
        #expect(model.places.map(\.distanceText) == ["à 10 m", "à 240 m", "à 530 m", "à 590 m"])
        #expect(model.radiusTitle == "Dans un rayon de 1 km")
        #expect(model.summaryText == "4 lieux dans ce rayon")
    }

    @Test func zoomingOutAddsPlacesWithoutReloading() async throws {
        let model = viewModel()
        await model.load()
        try zoom(model, to: 2_000)
        #expect(model.places.count == 8)
        #expect(Set(ids(model)).isSuperset(of: [ID.communityPickup, ID.moulinsDuNord]))
        #expect(!ids(model).contains(ID.hochelaga))

        try zoom(model, to: 6_000)
        #expect(ids(model).contains(ID.hochelaga))
        #expect(model.radiusTitle == "Dans un rayon de 6 km")
    }

    @Test func panningMovesTheAreaButDistancesStayFromTheFamily() async throws {
        let model = viewModel()
        await model.load()
        let home = try #require(model.origin?.coordinate)
        let hochelaga = try #require(model.allPlaces.value?.first { $0.sourceId == ID.hochelaga })
        // La famille glisse la carte jusqu'à Hochelaga, zoomée serré.
        model.applyVisibleArea(Area(center: hochelaga.coordinate, radiusMeters: 500))
        #expect(ids(model) == [ID.hochelaga])
        let distanceFromHome = Geohash.distanceMeters(from: home, to: hochelaga.coordinate)
        #expect(model.places.first?.distanceMeters == distanceFromHome)
        #expect(distanceFromHome > 4_000)
    }

    @Test func areaBoundaryIsInclusive() {
        let origin = Geohash.Coordinate(latitude: 45.5, longitude: -73.6)
        let place = FamilyMapViewModel.Place(
            detail: .group(NearbyGroupsFixture.group, isMember: false), coordinate: origin
        )
        // 999,9 m au nord (haversine) : gardé dans un rayon de 1 km ; 1 001 m : retiré.
        func moved(_ meters: Double) -> FamilyMapViewModel.Place {
            var copy = place
            copy.coordinate.latitude += meters / Self.metersPerDegree
            return copy
        }
        let area = Area(center: origin, radiusMeters: 1_000)
        let kept = FamilyMapViewModel.filter([moved(999.9)], in: area, distanceFrom: origin, kinds: Set(Kind.allCases))
        let dropped = FamilyMapViewModel.filter([moved(1_001)], in: area, distanceFrom: origin, kinds: Set(Kind.allCases))
        #expect(kept.count == 1)
        #expect(dropped.isEmpty)
    }

    @Test func countsPerKindFollowTheZoom() async throws {
        let model = viewModel()
        await model.load()
        try zoom(model, to: 1_000)
        #expect(model.countsInRadius == [.group: 1, .pickupPoint: 2, .producer: 1])
        try zoom(model, to: 2_000)
        #expect(model.countsInRadius == [.group: 1, .pickupPoint: 3, .producer: 4])
    }

    // MARK: Mouvements de carte (différés)

    @Test func cameraMovesAreDebouncedButTheIndicatorFollowsAtOnce() async throws {
        let model = viewModel(debounce: .milliseconds(80))
        await model.load()
        let center = try #require(model.origin?.coordinate)
        func region(_ meters: Double) -> (Double, Double) {
            let lat = meters / Self.metersPerDegree
            return (lat, lat / cos(center.latitude * .pi / 180))
        }

        // Pincement : trois positions coup sur coup, de 2 km à ≈ 1 km de côté.
        for side in [4_000.0, 2_000, 1_414] {
            let (lat, lon) = region(side)
            model.visibleRegionChanged(center: center, latitudeDelta: lat, longitudeDelta: lon)
        }
        // La pastille suit tout de suite, la liste attend la fin du geste.
        let live = try #require(model.liveRadiusMeters)
        #expect(abs(live - 1_000) < 10)
        #expect(model.radiusTitle == "Dans un rayon de 1 km")
        #expect(model.visibleArea == nil)
        #expect(model.places.count == 6)

        await model.settle()
        #expect(model.liveRadiusMeters == nil)
        #expect(abs((model.visibleArea?.radiusMeters ?? 0) - 1_000) < 10)
        #expect(model.places.count == 4)
    }

    // MARK: Sortes de lieux

    @Test func kindFilterHidesPlacesButKeepsAtLeastOneKind() async throws {
        let model = viewModel()
        await model.load()
        try zoom(model, to: 2_000)
        model.toggle(.group)
        model.toggle(.producer)
        #expect(model.places.allSatisfy { $0.kind == .pickupPoint })
        #expect(model.places.count == 3)
        // La dernière sorte visible ne peut pas être masquée.
        model.toggle(.pickupPoint)
        #expect(model.visibleKinds == [.pickupPoint])
        // Les puces comptent toujours toutes les sortes.
        #expect(model.countsInRadius[.producer] == 4)
    }

    @Test func emptyAreaIsEmptyState() async throws {
        var data = FakeData.montreal
        data.pickupPoints = []
        data.vendors = []
        data.groups.removeAll { $0.id == ID.saintMichel || $0.id == ID.villerayKitchen }
        let model = viewModel(data: data)
        await model.load()
        try zoom(model, to: 2_000)
        #expect(model.allPlaces.value?.map(\.sourceId) == [ID.hochelaga])
        #expect(model.state == .empty)
        #expect(model.summaryText == "Aucun lieu dans ce rayon")
    }

    // MARK: Sélection

    @Test func selectionDisappearsWhenThePlaceLeavesTheArea() async throws {
        let model = viewModel()
        await model.load()
        try zoom(model, to: 2_000)
        model.selectedPlaceID = "producer:\(ID.moulinsDuNord)"
        #expect(model.selectedPlace?.name == "Les Moulins du Nord")
        if case .producer(_, let offerId, let count) = model.selectedPlace?.detail {
            #expect(offerId == ID.riceOffer)
            #expect(count == 1)
        } else {
            Issue.record("Le lieu choisi devrait être un producteur")
        }
        try zoom(model, to: 1_000)
        #expect(model.selectedPlace == nil)
    }

    // MARK: Centre de la carte

    @Test func startsOnTheHouseholdNeighborhoodThenUsesTheUserLocation() async throws {
        let model = viewModel()
        await model.load()
        #expect(model.origin?.isUserLocation == false)
        #expect(model.origin?.title == "Autour de Saint-Michel")

        // Position autorisée, près du centre communautaire (≈ 1,8 km au sud du centre).
        let community = try #require(Geohash.center(of: "f25dv94"))
        #expect(model.useUserLocation(community))
        #expect(model.origin == .userLocation(community))
        #expect(model.origin?.title == "Autour de toi")
        #expect(model.places.first?.sourceId == ID.communityPickup)
        #expect(model.places.first?.distanceMeters ?? .infinity < 100)

        // Position refusée ensuite : retour au quartier.
        model.useHouseholdOrigin()
        #expect(model.origin?.isUserLocation == false)
        #expect(ids(model).first == ID.saintMichel)
    }

    @Test func farAwayLocationKeepsTheNeighborhood() async throws {
        let model = viewModel()
        await model.load()
        let cupertino = Geohash.Coordinate(latitude: 37.3349, longitude: -122.0090)
        #expect(!model.useUserLocation(cupertino))
        #expect(model.isUserLocationOutOfArea)
        #expect(model.origin?.isUserLocation == false)
        #expect(model.places.count == 6)
    }

    @Test func loadFailureIsAnError() async {
        let model = viewModel(behavior: .failing(.offline))
        await model.load()
        #expect(model.state.error != nil)
        #expect(model.places.isEmpty)
    }

    // MARK: Calculs

    @Test func placesSkipUnlocatedPointsAndDuplicateGroups() {
        let group = NearbyGroupsFixture.group
        var unlocated = FakeData.montreal.pickupPoints[0]
        unlocated.geohash = nil
        var invalid = unlocated
        invalid.id = "pickup-invalide"
        invalid.geohash = "aaaa"
        let places = FamilyMapViewModel.places(
            groups: [group, group], memberOf: [group.id], pickupPoints: [unlocated, invalid],
            vendors: FakeData.montreal.vendors.map { var vendor = $0; vendor.storefrontGeohash = nil; return vendor },
            offers: []
        )
        #expect(places.map(\.id) == ["group:\(group.id)"])
        if case .group(_, let isMember) = places.first?.detail { #expect(isMember) }
    }

    @Test func neighborhoodSlugsAreDisplayedNicely() {
        #expect(FamilyMapViewModel.displayName(ofNeighborhood: "parc-extension") == "Parc-Extension")
        #expect(FamilyMapViewModel.displayName(ofNeighborhood: "cote-des-neiges") == "Cote-des-Neiges")
        #expect(FamilyMapViewModel.displayName(ofNeighborhood: "Saint-Michel") == "Saint-Michel")
        #expect(FamilyMapViewModel.displayName(ofNeighborhood: "  ") == nil)
    }
}

private enum NearbyGroupsFixture {
    static let group = NeighborhoodGroup(
        id: "group-test", name: "Groupe test", neighborhood: "Villeray", centerGeohash: "f25dv", radiusMeters: 800,
        coordinatorIds: [], householdCount: 3, isPublic: true, inviteCode: "TEST"
    )
}
