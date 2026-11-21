import Foundation
import Testing
@testable import AMC_MobileApp

/// S-09 mise en relation (T-110) : groupes intéressés (vendeur) et offres correspondantes (famille).
@MainActor
struct MatchingViewModelsTests {
    private static let vendor = FakeData.ID.fermeRive
    private static let group = FakeData.ID.saintMichel
    private static let day: TimeInterval = 86_400

    private static func wish(_ household: String, _ category: Product.Category, _ quantity: Double,
                             group: String = group, id: String) -> GroupWish {
        GroupWish(id: id, groupId: group, householdId: household, category: category, quantity: quantity,
                  unit: .kilogram, frequency: .weekly, createdAt: .now)
    }

    private static func supply(_ category: Product.Category, zones: [String], id: String) -> VendorSupply {
        VendorSupply(id: id, vendorId: vendor, category: category, quantity: 100, unit: .kilogram,
                     availableFrom: .now, availableTo: .now.addingTimeInterval(10 * day), servedZones: zones)
    }

    private static func repositories(wishes: [GroupWish], supplies: [VendorSupply] = []) -> AppRepositories {
        var repos = AppRepositories.fake(behavior: .instant)
        repos.wishes = FakeGroupWishRepository(behavior: .instant, wishes: wishes)
        repos.supplies = FakeVendorSupplyRepository(behavior: .instant, supplies: supplies)
        return repos
    }

    // MARK: Groupes intéressés

    @Test func interestedGroupsListTheGroupsMyZonesReach() async throws {
        let groups = try await AppRepositories.fake(behavior: .instant).groups.groups(inNeighborhood: nil)
        let target = try #require(groups.first { $0.id == Self.group })
        let repos = Self.repositories(
            wishes: [Self.wish("h1", .produce, 30, id: "w1"), Self.wish("h2", .produce, 20, id: "w2")],
            supplies: [Self.supply(.produce, zones: [String(target.centerGeohash.prefix(3))], id: "s1")]
        )
        let model = InterestedGroupsViewModel(repositories: repos, vendorId: Self.vendor)
        await model.load()

        let interest = try #require(model.state.value?.first)
        #expect(interest.group.id == Self.group)
        #expect(interest.match.householdCount == 2)
        #expect(interest.topLine?.category == .produce)

        let targeted = try #require(model.targetedSupply(for: interest))
        #expect(targeted.id == "s1")
        #expect(targeted.servedZones == [target.centerGeohash.lowercased()])
    }

    @Test func noSupplyMeansNoInterestedGroup() async {
        let repos = Self.repositories(wishes: [Self.wish("h1", .produce, 30, id: "w1")])
        let model = InterestedGroupsViewModel(repositories: repos, vendorId: Self.vendor)
        await model.load()
        #expect(model.state == .empty)
    }

    @Test func aSupplyOutOfTheGroupZoneIsIgnored() async {
        let repos = Self.repositories(wishes: [Self.wish("h1", .produce, 30, id: "w1")],
                                      supplies: [Self.supply(.produce, zones: ["zzzz"], id: "s1")])
        let model = InterestedGroupsViewModel(repositories: repos, vendorId: Self.vendor)
        await model.load()
        #expect(model.state == .empty)
    }

    // MARK: Offres correspondantes

    @Test func withoutWishTheFamilyIsInvitedToSayOne() async {
        let model = MatchingOffersViewModel(repositories: Self.repositories(wishes: []), groupId: Self.group,
                                            householdId: FakeData.ID.aminaHousehold)
        await model.load()
        #expect(model.state == .empty)
        #expect(model.hasNoWish)
    }

    @Test func matchingOffersKeepOnlyWishedCategoriesServingTheGroup() async throws {
        let base = AppRepositories.fake(behavior: .instant)
        let group = try await base.groups.group(id: Self.group)
        let served = try await base.offers.activeOffers(inZone: nil)
            .filter { OfferSummaryLoader.offer($0, serves: group) && $0.deadline > .now }
        let first = try #require(served.first)
        let category = try await base.vendors.product(id: first.productId).category

        let me = FakeData.ID.aminaHousehold
        let model = MatchingOffersViewModel(
            repositories: Self.repositories(wishes: [Self.wish(me, category, 5, id: "w1"),
                                                     Self.wish("voisin", .grains, 5, id: "w2")]),
            groupId: Self.group, householdId: me
        )
        await model.load()

        let items = try #require(model.state.value)
        #expect(!model.hasNoWish)
        #expect(items.contains { $0.offer.id == first.id })
        #expect(items.allSatisfy { $0.product.category == category })
        #expect(items.map(\.offer.deadline) == items.map(\.offer.deadline).sorted())
    }
}
