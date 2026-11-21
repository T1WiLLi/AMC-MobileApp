import Foundation
import Testing
@testable import AMC_MobileApp

/// S-07, S-08 : envies des familles, agrégat anonyme et disponibilités des vendeurs (dépôts fake).
struct FakeMatchingRepositoryTests {
    private typealias ID = FakeData.ID
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    static func wish(_ household: String, _ category: Product.Category, _ quantity: Double,
                     unit: MeasureUnit = .kilogram, group: String = ID.saintMichel) -> GroupWish {
        GroupWish(groupId: group, householdId: household, category: category, quantity: quantity, unit: unit,
                  frequency: .monthly)
    }

    static func supply(_ quantity: Double = 50, vendor: String = ID.fermeRive) -> VendorSupply {
        VendorSupply(vendorId: vendor, category: .produce, quantity: quantity, unit: .kilogram,
                     availableFrom: start, availableTo: start.addingTimeInterval(86_400), servedZones: ["f25d"])
    }

    // MARK: Agrégat

    @Test func demandSumsByCategoryAndCountsHouseholdsOnce() {
        let demand = GroupDemand.aggregate([
            Self.wish("h1", .grains, 10), Self.wish("h1", .grains, 5), Self.wish("h2", .grains, 20),
            Self.wish("h3", .eggs, 2, unit: .dozen), Self.wish("h3", .eggs, 1, unit: .unit),
        ])
        #expect(demand.map(\.id) == ["grains-kg", "eggs-dozen", "eggs-unit"])
        #expect(demand[0].totalQuantity == 35)
        #expect(demand[0].householdCount == 2)
        #expect(demand[1].householdCount == 1)
    }

    @Test func demoDemandOfSaintMichel() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let demand = try await repos.wishes.demand(ofGroup: ID.saintMichel)
        let grains = try #require(demand.first { $0.category == .grains })
        #expect(grains.totalQuantity == 40)
        #expect(grains.householdCount == 3)
        #expect(try await repos.wishes.demand(ofGroup: "group-inconnu").isEmpty)
    }

    // MARK: Envies

    @Test func addUpdateRemoveAWish() async throws {
        let repo = FakeGroupWishRepository()
        let created = try await repo.addWish(Self.wish(ID.aminaHousehold, .oils, 3, unit: .liter))
        #expect(!created.id.isEmpty)
        #expect(try await repo.wishes(ofHousehold: ID.aminaHousehold, inGroup: ID.saintMichel).map(\.id) == [created.id])

        var changed = created
        changed.quantity = 5
        let updated = try await repo.updateWish(changed)
        #expect(updated.quantity == 5)
        #expect(updated.createdAt == created.createdAt)

        try await repo.removeWish(id: created.id, groupId: ID.saintMichel)
        #expect(try await repo.wishes(ofGroup: ID.saintMichel).isEmpty)
        await #expect(throws: AppError.notFound) { try await repo.removeWish(id: created.id, groupId: ID.saintMichel) }
    }

    @Test func wishCannotMoveToAnotherHouseholdOrBeInvalid() async throws {
        let repo = FakeGroupWishRepository()
        let created = try await repo.addWish(Self.wish("h1", .grains, 10))
        var stolen = created
        stolen.householdId = "h2"
        await #expect(throws: AppError.permissionDenied) { try await repo.updateWish(stolen) }
        await #expect(throws: AppError.self) { try await repo.addWish(Self.wish("h1", .grains, 0)) }
        await #expect(throws: AppError.notFound) { try await repo.updateWish(Self.wish("h1", .grains, 1)) }
    }

    @Test func observeDemandFollowsNewWishes() async throws {
        let repo = FakeGroupWishRepository()
        let stream = await repo.observeDemand(ofGroup: ID.saintMichel)
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == [])
        try await repo.addWish(Self.wish("h1", .grains, 10))
        let next = try #require(try await iterator.next())
        #expect(next.map(\.totalQuantity) == [10])
    }

    // MARK: Disponibilités

    @Test func addUpdateRemoveASupply() async throws {
        let repo = FakeVendorSupplyRepository()
        let stream = await repo.observeSupplies(ofVendor: ID.fermeRive)
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == [])

        let created = try await repo.addSupply(Self.supply())
        #expect(try await iterator.next()?.map(\.id) == [created.id])

        var changed = created
        changed.quantity = 20
        #expect(try await repo.updateSupply(changed).quantity == 20)
        var moved = created
        moved.vendorId = ID.moulinsDuNord
        await #expect(throws: AppError.permissionDenied) { try await repo.updateSupply(moved) }

        try await repo.removeSupply(id: created.id, vendorId: ID.fermeRive)
        #expect(try await repo.allSupplies().isEmpty)
    }

    @Test func supplyNeedsZonesAndAValidPeriod() async {
        let repo = FakeVendorSupplyRepository()
        var noZone = Self.supply()
        noZone.servedZones = []
        await #expect(throws: AppError.self) { try await repo.addSupply(noZone) }
        var reversed = Self.supply()
        reversed.availableTo = reversed.availableFrom.addingTimeInterval(-1)
        await #expect(throws: AppError.self) { try await repo.addSupply(reversed) }
    }
}
