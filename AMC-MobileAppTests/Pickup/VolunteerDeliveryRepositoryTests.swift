import Foundation
import Testing
@testable import AMC_MobileApp

/// Dépôt fake et ViewModel de la livraison par un voisin bénévole (RQ-069, T-117).
struct VolunteerDeliveryRepositoryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func request(_ id: String = "r1", household: String = "h1") -> VolunteerDelivery.Request {
        let start = now.addingTimeInterval(3_600)
        return VolunteerDelivery.Request(
            id: id, groupId: "g1", groupOrderId: "go1", householdId: household, householdName: "Mme Tremblay",
            geohash: "f25dvg", quantity: 2, window: .init(start: start, end: start.addingTimeInterval(7_200)),
            reason: .senior, note: nil, status: .requested, createdAt: now
        )
    }

    private func address(_ id: String = "r1") -> VolunteerDelivery.PrivateAddress {
        .init(requestId: id, address: "4521 rue Jarry Est", instructions: nil)
    }

    private func repository() -> FakeVolunteerDeliveryRepository {
        let now = now
        return FakeVolunteerDeliveryRepository(now: { now })
    }

    @Test func twoNeighboursCompeteForTheSameDeliveryOnlyOneWins() async throws {
        let repo = repository()
        try await repo.createDelivery(request(), address: address())
        async let first: VolunteerDelivery.Request? = try? repo.claimDelivery(
            id: "r1", groupOrderId: "go1", volunteerHouseholdId: "v1", volunteerName: "Karim", volunteerGroupIds: ["g1"]
        )
        async let second: VolunteerDelivery.Request? = try? repo.claimDelivery(
            id: "r1", groupOrderId: "go1", volunteerHouseholdId: "v2", volunteerName: "Lina", volunteerGroupIds: ["g1"]
        )
        let winners = await [first, second].compactMap { $0 }
        #expect(winners.count == 1)
        let stored = try await repo.deliveries(ofGroup: "g1")
        #expect(stored.first?.volunteerHouseholdId == winners.first?.volunteerHouseholdId)
    }

    @Test func duplicateActiveRequestIsRefused() async throws {
        let repo = repository()
        try await repo.createDelivery(request(), address: address())
        await #expect(throws: AppError.self) {
            try await repo.createDelivery(request("r2"), address: address("r2"))
        }
    }

    @Test func addressIsOnlyRevealedToHouseholdAndItsVolunteer() async throws {
        let repo = repository()
        try await repo.createDelivery(request(), address: address())
        #expect(try await repo.address(ofDelivery: "r1", groupOrderId: "go1", viewerHouseholdId: "v1") == nil)
        #expect(try await repo.address(ofDelivery: "r1", groupOrderId: "go1", viewerHouseholdId: "h1") != nil)
        try await repo.claimDelivery(id: "r1", groupOrderId: "go1", volunteerHouseholdId: "v1", volunteerName: "Karim",
                                     volunteerGroupIds: ["g1"])
        #expect(try await repo.address(ofDelivery: "r1", groupOrderId: "go1", viewerHouseholdId: "v1") != nil)
        #expect(try await repo.address(ofDelivery: "r1", groupOrderId: "go1", viewerHouseholdId: "v2") == nil)
    }

    @Test func fullJourneyEndsDeliveredAndConfirmed() async throws {
        let repo = repository()
        try await repo.createDelivery(request(), address: address())
        try await repo.claimDelivery(id: "r1", groupOrderId: "go1", volunteerHouseholdId: "v1", volunteerName: "Karim",
                                     volunteerGroupIds: ["g1"])
        await #expect(throws: AppError.self) {
            try await repo.markDelivered(id: "r1", groupOrderId: "go1", volunteerHouseholdId: "v1")
        }
        try await repo.startRoute(id: "r1", groupOrderId: "go1", volunteerHouseholdId: "v1")
        await #expect(throws: AppError.self) {
            try await repo.cancelDelivery(id: "r1", groupOrderId: "go1", householdId: "h1")
        }
        let delivered = try await repo.markDelivered(id: "r1", groupOrderId: "go1", volunteerHouseholdId: "v1")
        #expect(delivered.status == .delivered)
        let confirmed = try await repo.confirmReceipt(id: "r1", groupOrderId: "go1", householdId: "h1")
        #expect(confirmed.receiptConfirmedAt == now)
    }

    @Test func releasedDeliveryIsOpenAgain() async throws {
        let repo = repository()
        try await repo.createDelivery(request(), address: address())
        try await repo.claimDelivery(id: "r1", groupOrderId: "go1", volunteerHouseholdId: "v1", volunteerName: "Karim",
                                     volunteerGroupIds: ["g1"])
        let released = try await repo.releaseDelivery(id: "r1", groupOrderId: "go1", volunteerHouseholdId: "v1")
        #expect(released.status == .requested)
        #expect(released.volunteerHouseholdId == nil)
    }

    @MainActor
    @Test func volunteerViewModelListsOpenRequestsNearestFirstAndClaims() async throws {
        let model = VolunteerDeliveryViewModel(
            repositories: .fake(behavior: .instant), userId: FakeData.ID.amina,
            householdId: FakeData.ID.aminaHousehold, groupId: FakeData.ID.saintMichel, mode: .volunteer
        )
        await model.load()
        let content = try #require(model.state.value)
        #expect(content.openItems.count == 3)
        #expect(content.activeDeliveries.count == 1)
        #expect(content.addresses[content.activeDeliveries[0].id] != nil)
        let distances = content.openItems.compactMap(\.distanceMeters)
        #expect(distances == distances.sorted())

        await model.claim(content.openItems[0].request)
        #expect(model.actionError == nil)
        #expect(model.successes == 1)
        #expect(model.state.value?.activeDeliveries.count == 2)
    }

    @MainActor
    @Test func volunteerMarksDeliveredAndSeesTheSuccessScene() async throws {
        let model = VolunteerDeliveryViewModel(
            repositories: .fake(behavior: .instant), userId: FakeData.ID.amina,
            householdId: FakeData.ID.aminaHousehold, groupId: FakeData.ID.saintMichel, mode: .volunteer
        )
        await model.load()
        let active = try #require(model.state.value?.activeDeliveries.first)
        await model.startRoute(active)
        await model.markDelivered(active)
        #expect(model.justDelivered?.status == .delivered)
        #expect(model.state.value?.completedDeliveries.count == 1)
    }
}
