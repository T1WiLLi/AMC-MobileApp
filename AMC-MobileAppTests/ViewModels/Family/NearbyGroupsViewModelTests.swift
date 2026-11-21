import Foundation
import Testing
@testable import AMC_MobileApp

/// T-063 : groupes à proximité (RQ-023) et groupe suggéré (RQ-031).
/// Amina habite en f25dv (Saint-Michel, dont elle est membre). Hochelaga (f25ej) est à ≈ 4,9 km.
/// Jeu étendu : Jarry (f25dvk, ≈ 530 m), Villeray (f25dvu, ≈ 1,3 km), un groupe privé tout près (f25dvs).
@MainActor
struct NearbyGroupsViewModelTests {
    private typealias ID = FakeData.ID
    private static let jarry = "group-jarry"
    private static let villeray = "group-villeray"
    private static let hidden = "group-prive"

    private static func group(_ id: String, _ name: String, geohash: String, households: Int,
                              isPublic: Bool = true) -> NeighborhoodGroup {
        NeighborhoodGroup(id: id, name: name, neighborhood: "Villeray", centerGeohash: geohash, radiusMeters: 800,
                          coordinatorIds: [], householdCount: households, isPublic: isPublic, inviteCode: id)
    }

    private static var extendedData: FakeData {
        var data = FakeData.montreal
        data.groups += [
            group(villeray, "Villeray en commun", geohash: "f25dvu", households: 1),
            group(jarry, "Parc Jarry", geohash: "f25dvk", households: 8),
            group(hidden, "Immeuble privé", geohash: "f25dvs", households: 4, isPublic: false),
        ]
        return data
    }

    private func viewModel(
        data: FakeData = extendedData, behavior: FakeBehavior = .instant,
        origin: NearbyGroupsViewModel.Origin = .household
    ) -> NearbyGroupsViewModel {
        NearbyGroupsViewModel(repositories: .fake(behavior: behavior, data: data),
                              householdId: ID.aminaHousehold, origin: origin)
    }

    // MARK: Liste

    @Test func listsPublicGroupsWithinTwoKilometersByDistance() async throws {
        let model = viewModel()
        #expect(model.radius == .twoKilometers)
        await model.load()
        let items = try #require(model.state.value)
        #expect(items.map(\.id) == [ID.saintMichel, Self.jarry, Self.villeray])
        #expect(items.map(\.isMember) == [true, false, false])
        #expect(items.map(\.distanceText) == ["à 10 m", "à 530 m", "à 1,3 km"])
        #expect(items[1].memberCount == 8)
        #expect(items[1].memberCountText == "8 ménages")
        #expect(items[2].memberCountText == "1 ménage")
        // Le groupe privé n'apparaît jamais ; Hochelaga est chargé mais hors rayon.
        #expect(model.allGroups.value?.map(\.id).contains(Self.hidden) == false)
        #expect(model.allGroups.value?.last?.id == ID.hochelaga)
    }

    @Test func radiusFiltersWithoutReloading() async throws {
        let model = viewModel()
        await model.load()
        model.radius = .oneKilometer
        #expect(model.items.map(\.id) == [ID.saintMichel, Self.jarry])
        model.radius = .twoKilometers
        #expect(model.items.map(\.id) == [ID.saintMichel, Self.jarry, Self.villeray])
        #expect(NearbyGroupsViewModel.Radius.allCases.map(\.title) == ["1 km", "2 km"])
    }

    @Test func suggestsTheNearestGroupTheHouseholdIsNotIn() async throws {
        let model = viewModel()
        #expect(model.suggestedGroup == nil)
        await model.load()
        #expect(model.suggestedGroup?.id == Self.jarry)

        // Données de base : seul Saint-Michel est à moins de 2 km, et Amina en fait déjà partie.
        let base = viewModel(data: .montreal)
        await base.load()
        #expect(base.items.map(\.id) == [ID.saintMichel])
        #expect(base.suggestedGroup == nil)
    }

    @Test func joinMarksTheGroupAndMovesTheSuggestion() async throws {
        let model = viewModel()
        await model.load()
        await model.join(groupId: Self.jarry)
        #expect(model.actionError == nil)
        #expect(model.pendingGroupIds.isEmpty)
        let jarry = try #require(model.items.first { $0.id == Self.jarry })
        #expect(jarry.isMember)
        #expect(jarry.memberCount == 9)
        #expect(model.suggestedGroup?.id == Self.villeray)
    }

    @Test func joinFailureIsReported() async {
        let model = viewModel()
        await model.load()
        await model.join(groupId: "group-inconnu")
        #expect(model.actionError == .notFound)
    }

    // MARK: Origine

    @Test func measuresFromAGeohashOrACoordinate() async throws {
        let fromHochelaga = viewModel(origin: .geohash("f25ej"))
        await fromHochelaga.load()
        #expect(fromHochelaga.items.map(\.id) == [ID.hochelaga])
        #expect(fromHochelaga.suggestedGroup?.id == ID.hochelaga)

        let coordinate = try #require(Geohash.center(of: "f25dvk"))
        let fromJarry = viewModel(origin: .coordinate(coordinate))
        await fromJarry.load()
        #expect(fromJarry.items.first?.id == Self.jarry)
        #expect(fromJarry.items.first?.distanceMeters == 0)
    }

    @Test func unknownHouseholdLocationFails() async {
        var data = Self.extendedData
        data.households[0].geohash = ""
        let model = viewModel(data: data)
        await model.load()
        #expect(model.state.error == .invalidInput("La position du ménage est inconnue."))
    }

    // MARK: États

    @Test func emptyWhenNoGroupIsNearby() async {
        // Québec : aucun groupe à moins de 2 km, mais des groupes sont chargés.
        let model = viewModel(origin: .coordinate(Geohash.Coordinate(latitude: 46.8139, longitude: -71.2080)))
        await model.load()
        #expect(model.state == .empty)
        #expect(model.allGroups.value?.isEmpty == false)
        #expect(model.suggestedGroup == nil)

        var data = FakeData.montreal
        data.groups = []
        let none = viewModel(data: data)
        await none.load()
        #expect(none.allGroups == .empty)
        #expect(none.state == .empty)
    }

    @Test func failingRepositoryFails() async {
        let model = viewModel(behavior: .failing())
        await model.load()
        #expect(model.state == .failed(.offline))
        #expect(model.suggestedGroup == nil)
    }

    // MARK: Distance en français

    @Test func distanceTextIsFrench() {
        #expect(NearbyGroupsViewModel.distanceText(meters: 0) == "à 10 m")
        #expect(NearbyGroupsViewModel.distanceText(meters: 648) == "à 650 m")
        #expect(NearbyGroupsViewModel.distanceText(meters: 994) == "à 990 m")
        #expect(NearbyGroupsViewModel.distanceText(meters: 996) == "à 1,0 km")
        #expect(NearbyGroupsViewModel.distanceText(meters: 1_420) == "à 1,4 km")
        #expect(NearbyGroupsViewModel.distanceText(meters: 2_000) == "à 2,0 km")
        #expect(NearbyGroupsViewModel.distanceText(meters: 12_300) == "à 12 km")
    }
}
