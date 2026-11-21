import Foundation
import Testing
@testable import AMC_MobileApp

/// T-091 : carte des familles, filtre par rayon (1 / 1,5 / 2 km), par sorte de lieu et centre de la carte.
/// Amina habite en f25dv (Saint-Michel). Autour : le groupe Saint-Michel (centre), trois points de cueillette
/// (≈ 235 m à 1,8 km) et quatre producteurs (≈ 535 m à 1,9 km). Hochelaga (≈ 4,9 km) n'est jamais dans le rayon.
@MainActor
struct FamilyMapViewModelTests {
    private typealias ID = FakeData.ID
    private typealias Kind = FamilyMapViewModel.Kind

    private func viewModel(
        data: FakeData = .montreal, behavior: FakeBehavior = .instant,
        radius: FamilyMapViewModel.Radius = .oneAndHalfKilometers
    ) -> FamilyMapViewModel {
        FamilyMapViewModel(repositories: .fake(behavior: behavior, data: data), householdId: ID.aminaHousehold,
                           userId: ID.amina, radius: radius)
    }

    private func ids(_ model: FamilyMapViewModel) -> [String] { model.places.map(\.sourceId) }

    // MARK: Rayon

    @Test func oneKilometerShowsTheClosestPlacesByDistance() async throws {
        let model = viewModel(radius: .oneKilometer)
        await model.load()
        #expect(ids(model) == [ID.saintMichel, ID.jarryPickup, ID.fournil, ID.pieIXPickup])
        #expect(model.places.map(\.kind) == [.group, .pickupPoint, .producer, .pickupPoint])
        #expect(model.places.map(\.distanceText) == ["à 10 m", "à 240 m", "à 530 m", "à 590 m"])
        #expect(model.places.allSatisfy { $0.distanceMeters <= 1_000 })
        #expect(model.summaryText == "4 lieux à moins de 1 km")
    }

    @Test func widerRadiusAddsPlacesWithoutReloading() async throws {
        let model = viewModel()
        await model.load()
        #expect(model.radius == .oneAndHalfKilometers)
        #expect(model.places.count == 6)
        #expect(model.places.allSatisfy { $0.distanceMeters <= 1_500 })

        model.radius = .twoKilometers
        #expect(model.places.count == 8)
        #expect(Set(ids(model)).isSuperset(of: [ID.communityPickup, ID.moulinsDuNord]))
        #expect(!ids(model).contains(ID.hochelaga))

        model.radius = .oneKilometer
        #expect(model.places.count == 4)
        #expect(FamilyMapViewModel.Radius.allCases.map(\.title) == ["1 km", "1,5 km", "2 km"])
    }

    @Test func radiusBoundaryIsInclusive() {
        let origin = Geohash.Coordinate(latitude: 45.5, longitude: -73.6)
        let place = FamilyMapViewModel.Place(
            detail: .group(NearbyGroupsFixture.group, isMember: false), coordinate: origin
        )
        // Exactement 1 000 m au nord (haversine) : gardé ; 1 001 m : retiré.
        let metersPerDegree = Geohash.earthRadiusMeters * .pi / 180
        func moved(_ meters: Double) -> FamilyMapViewModel.Place {
            var copy = place
            copy.coordinate.latitude += meters / metersPerDegree
            return copy
        }
        let kept = FamilyMapViewModel.filter([moved(999.9)], around: origin, radius: .oneKilometer, kinds: Set(Kind.allCases))
        let dropped = FamilyMapViewModel.filter([moved(1_001)], around: origin, radius: .oneKilometer, kinds: Set(Kind.allCases))
        #expect(kept.count == 1)
        #expect(dropped.isEmpty)
    }

    @Test func countsPerKindFollowTheRadius() async throws {
        let model = viewModel(radius: .oneKilometer)
        await model.load()
        #expect(model.countsInRadius == [.group: 1, .pickupPoint: 2, .producer: 1])
        model.radius = .twoKilometers
        #expect(model.countsInRadius == [.group: 1, .pickupPoint: 3, .producer: 4])
    }

    // MARK: Sortes de lieux

    @Test func kindFilterHidesPlacesButKeepsAtLeastOneKind() async throws {
        let model = viewModel(radius: .twoKilometers)
        await model.load()
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

    @Test func emptyRadiusIsEmptyState() async throws {
        var data = FakeData.montreal
        data.pickupPoints = []
        data.vendors = []
        data.groups.removeAll { $0.id == ID.saintMichel }
        let model = viewModel(data: data, radius: .twoKilometers)
        await model.load()
        #expect(model.allPlaces.value?.map(\.sourceId) == [ID.hochelaga])
        #expect(model.state == .empty)
        #expect(model.summaryText == "0 lieu à moins de 2 km")
    }

    // MARK: Sélection

    @Test func selectionDisappearsWhenThePlaceLeavesTheRadius() async throws {
        let model = viewModel(radius: .twoKilometers)
        await model.load()
        model.selectedPlaceID = "producer:\(ID.moulinsDuNord)"
        #expect(model.selectedPlace?.name == "Les Moulins du Nord")
        if case .producer(_, let offerId, let count) = model.selectedPlace?.detail {
            #expect(offerId == ID.riceOffer)
            #expect(count == 1)
        } else {
            Issue.record("Le lieu choisi devrait être un producteur")
        }
        model.radius = .oneKilometer
        #expect(model.selectedPlace == nil)
    }

    // MARK: Centre de la carte

    @Test func startsOnTheHouseholdNeighborhoodThenUsesTheUserLocation() async throws {
        let model = viewModel(radius: .oneKilometer)
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
