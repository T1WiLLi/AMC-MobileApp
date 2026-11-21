import Foundation
import Testing
@testable import AMC_MobileApp

/// Fixtures de démo des ménages, commandes groupées et parts (B-028, T-049).
/// Elles doivent se décoder avec les modèles Swift et rester cohérentes avec les règles de paliers.
struct SeedHouseholdsFixtureTests {
    private static let fixtures = URL(filePath: #filePath)
        .deletingLastPathComponent()  // Seed/
        .deletingLastPathComponent()  // AMC-MobileAppTests/
        .deletingLastPathComponent()  // racine du repo
        .appending(path: "scripts/seed/fixtures")

    private static let expectedMembers: [String: Int] = [
        "group-parc-extension": 10, "group-rosemont": 8, "group-hochelaga": 7, "group-saint-michel": 7,
        "group-verdun": 7, "group-cote-des-neiges": 7, "group-montreal-nord": 7, "group-villeray": 7,
    ]

    /// Un ménage tel qu'écrit dans `households.json` : le modèle plus les champs propres au seed.
    nonisolated struct SeedHousehold: Decodable {
        enum Role: String, Decodable { case member, coordinator }
        var household: Household
        var groupId: String
        var memberRole: Role
        var `private`: HouseholdPrivate

        private enum CodingKeys: String, CodingKey { case groupId, memberRole, `private` }

        init(from decoder: any Decoder) throws {
            household = try Household(from: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            groupId = try container.decode(String.self, forKey: .groupId)
            memberRole = try container.decode(Role.self, forKey: .memberRole)
            `private` = try container.decode(HouseholdPrivate.self, forKey: .private)
        }
    }

    nonisolated struct SeedOrder {
        var order: GroupOrder
        var shares: [Share]
    }

    private func data(_ name: String) throws -> Data {
        try Data(contentsOf: Self.fixtures.appending(path: "\(name).json"))
    }

    private func households() throws -> [SeedHousehold] {
        try JSONDecoder().decode([SeedHousehold].self, from: data("households"))
    }

    /// Même conversion que le script : `pickupSlotsInDays` devient `pickupSlots`, `shares` est une sous-collection.
    private func orders() throws -> [SeedOrder] {
        let raw = try #require(try JSONSerialization.jsonObject(with: data("groupOrders")) as? [[String: Any]])
        let startOfToday = Calendar.current.startOfDay(for: .now)
        return try raw.map { entry in
            var entry = entry
            let rawSlots = entry.removeValue(forKey: "pickupSlotsInDays")
            let slots = try #require(rawSlots as? [[String: Int]])
            entry["pickupSlots"] = try slots.map { slot in
                let day = startOfToday.addingTimeInterval(Double(try #require(slot["inDays"])) * 86_400)
                return [
                    "start": day.addingTimeInterval(Double(try #require(slot["startHour"])) * 3_600).timeIntervalSinceReferenceDate,
                    "end": day.addingTimeInterval(Double(try #require(slot["endHour"])) * 3_600).timeIntervalSinceReferenceDate,
                ]
            }
            let removed = entry.removeValue(forKey: "shares")
            let shares = try #require(removed as? [[String: Any]])
            let decoder = JSONDecoder()
            return SeedOrder(
                order: try decoder.decode(GroupOrder.self, from: JSONSerialization.data(withJSONObject: entry)),
                shares: try decoder.decode([Share].self, from: JSONSerialization.data(withJSONObject: shares))
            )
        }
    }

    private func offers() throws -> [String: Offer] {
        let raw = try #require(try JSONSerialization.jsonObject(with: data("offers")) as? [[String: Any]])
        let converted: [[String: Any]] = try raw.map { offer in
            var offer = offer
            let days = try #require(offer.removeValue(forKey: "deadlineInDays") as? Int)
            offer["deadline"] = Date.now.timeIntervalSinceReferenceDate + Double(days) * 86_400
            return offer
        }
        let offers = try JSONDecoder().decode([Offer].self, from: JSONSerialization.data(withJSONObject: converted))
        return Dictionary(uniqueKeysWithValues: offers.map { ($0.id, $0) })
    }

    private func sharesToNextTier(_ order: GroupOrder, _ offer: Offer) -> Int? {
        offer.nextTier(afterCommittedShares: order.committedShares).map { $0.minShares - order.committedShares }
    }

    @Test func sixtyUniqueHouseholdsIncludingPersonas() throws {
        let households = try households()
        #expect(households.count == 60)
        let ids = Set(households.map(\.household.id))
        #expect(ids.count == 60)
        #expect(ids.isSuperset(of: ["household-amina", "household-jean"]))
        #expect(households.allSatisfy { $0.household.size >= 1 && !$0.household.geohash.isEmpty })
        let amina = try #require(households.first { $0.household.id == "household-amina" })
        #expect(amina.groupId == "group-parc-extension" && amina.household.userIds == ["user-amina"])
        let jean = try #require(households.first { $0.household.id == "household-jean" })
        #expect(jean.groupId == "group-parc-extension" && jean.household.userIds == ["user-jean"])
    }

    @Test func membershipCountsAndOneCoordinatorPerGroup() throws {
        let byGroup = Dictionary(grouping: try households(), by: \.groupId)
        #expect(byGroup.mapValues(\.count) == Self.expectedMembers)
        for (group, members) in byGroup {
            #expect(members.filter { $0.memberRole == .coordinator }.count == 1, "\(group)")
        }
    }

    @Test func aboutFifteenPercentAreSubsidized() throws {
        let subsidized = try households().filter(\.private.isSubsidized).count
        #expect((6...12).contains(subsidized))
    }

    @Test func everyOrderUsesAnActiveOfferServingTheGroup() throws {
        let offers = try offers()
        let orders = try orders()
        #expect(orders.count >= 12)
        #expect(Set(orders.map(\.order.id)).count == orders.count)
        #expect(Set(orders.map(\.order.groupId)) == Set(Self.expectedMembers.keys))
        for entry in orders {
            let order = entry.order
            let offer = try #require(offers[order.offerId], "\(order.id) : lot inconnu")
            let slug = String(order.groupId.dropFirst("group-".count))
            #expect(offer.status == .active, "\(order.id)")
            #expect(offer.zones.contains(slug), "\(order.id)")
            #expect(order.id.hasPrefix("order-\(slug)-"), "\(order.id)")
            #expect(order.pickupPointId == "pickup-\(slug)-1", "\(order.id)")
            #expect(!order.pickupSlots.isEmpty && order.pickupSlots.allSatisfy { $0.start < $0.end }, "\(order.id)")
        }
    }

    @Test func everyShareBelongsToAMemberOfTheGroup() throws {
        let households = try households()
        let groupOf = Dictionary(uniqueKeysWithValues: households.map { ($0.household.id, $0.groupId) })
        let subsidized = Set(households.filter(\.private.isSubsidized).map(\.household.id))
        for entry in try orders() {
            #expect(Set(entry.shares.map(\.householdId)).count == entry.shares.count, "\(entry.order.id)")
            for share in entry.shares {
                #expect(groupOf[share.householdId] == entry.order.groupId, "\(entry.order.id) : \(share.householdId)")
                #expect(share.quantity >= 1, "\(entry.order.id)")
                #expect(share.subsidyCents == 0 || subsidized.contains(share.householdId), "\(entry.order.id)")
            }
        }
    }

    @Test func denormalizedTotalsMatchSharesAndTiers() throws {
        let offers = try offers()
        for entry in try orders() {
            let order = entry.order
            let offer = try #require(offers[order.offerId])
            #expect(order.committedShares == entry.shares.map(\.quantity).reduce(0, +), "\(order.id)")
            #expect(order.committedHouseholds == entry.shares.count, "\(order.id)")
            #expect(order.committedShares <= offer.totalShares, "\(order.id)")
            #expect(order.currentTierIndex == offer.tierIndex(forCommittedShares: order.committedShares), "\(order.id)")
            let expected: GroupOrder.Status = order.committedShares >= offer.minimumSharesToLaunch ? .reached : .open
            #expect(order.status == expected, "\(order.id)")
            #expect(try TierEngine.recalculated(order, offer: offer, shares: entry.shares) == order, "\(order.id)")
        }
    }

    @Test func someBasketsAreSuspended() throws {
        #expect(try orders().flatMap(\.shares).contains { $0.suspendedAmountCents > 0 })
    }

    @Test func atLeastThreeOrdersAreOneFamilyAway() throws {
        let offers = try offers()
        let close = try orders().filter { entry in
            guard let offer = offers[entry.order.offerId], let gap = sharesToNextTier(entry.order, offer) else { return false }
            return (1...2).contains(gap)
        }
        #expect(close.count >= 3)
    }

    /// Démo : Amina rejoint la commande de Parc-Extension et fait franchir le palier.
    @Test func parcExtensionDemoOrderExcludesAmina() throws {
        let offers = try offers()
        let demo = try #require(try orders().first { entry in
            guard entry.order.groupId == "group-parc-extension",
                  let offer = offers[entry.order.offerId],
                  let gap = sharesToNextTier(entry.order, offer) else { return false }
            return (1...2).contains(gap) && !entry.shares.contains { $0.householdId == "household-amina" }
        })
        #expect(demo.order.status == .open || demo.order.status == .reached)
    }
}
