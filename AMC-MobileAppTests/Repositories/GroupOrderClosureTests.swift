import Foundation
import Testing
@testable import AMC_MobileApp

/// E21-2 : clôture d'une commande et paiement simulé des parts au pot, avec `FakeGroupOrderRepository`.
struct GroupOrderClosureTests {
    static let offer = TierEngineTests.offer
    static let deadline = TierEngineTests.deadline
    static let before = deadline.addingTimeInterval(-3_600)
    static let after = deadline.addingTimeInterval(3_600)

    static let coordinator = ClosurePolicyTests.user(household: "h1")
    static let coordinatorMembership = ClosurePolicyTests.member("h1", role: .coordinator)

    /// Commande « go1 » : h1 6 parts, h2 8 parts, h3 8 parts (22 parts → palier à 9,90 $), ou `shares` donnés.
    static func repository(
        shares: [Share] = [TierEngineTests.share("h1", 6), TierEngineTests.share("h2", 8), TierEngineTests.share("h3", 8)],
        now: Date = before,
        outcome: PaymentSimulator.Outcome = .success
    ) -> FakeGroupOrderRepository {
        let committed = shares.reduce(0) { $0 + $1.quantity }
        var order = TierEngineTests.order(committed: committed, status: committed >= offer.minimumSharesToLaunch ? .reached : .open)
        order.committedHouseholds = shares.count
        return FakeGroupOrderRepository(
            groupOrders: [order], shares: [order.id: shares], offers: [offer], now: { now },
            payments: PaymentSimulator(outcome: outcome, now: { now })
        )
    }

    static let manual = GroupOrderClosureTrigger.manual(user: coordinator, membership: coordinatorMembership)

    @Test func confirmedClosurePaysEveryShareAtTheFrozenTierPrice() async throws {
        let repository = Self.repository()
        let closure = try await repository.closeGroupOrder(id: "go1", trigger: Self.manual)

        #expect(closure.outcome == .confirmed(tierIndex: 1, unitPriceCents: 990))
        #expect(closure.order.status == .closed)
        #expect(closure.paidCount == 3)
        #expect(closure.payments.allSatisfy { $0.status == .succeeded })

        let shares = try await repository.shares(ofGroupOrder: "go1")
        #expect(shares.allSatisfy { $0.isPaid })
        #expect(shares.allSatisfy { $0.finalPriceCents == $0.quantity * 990 })
        #expect(closure.payments.map(\.amountDueCents).sorted() == [6 * 990, 8 * 990, 8 * 990])
        #expect(try await repository.groupOrder(id: "go1").status == .closed)
    }

    @Test func declinedSimulatorLeavesSharesUnpaid() async throws {
        let repository = Self.repository(outcome: .declined)
        let closure = try await repository.closeGroupOrder(id: "go1", trigger: Self.manual)

        #expect(closure.order.status == .closed)
        #expect(closure.declinedCount == 3)
        #expect(closure.paidCount == 0)
        let shares = try await repository.shares(ofGroupOrder: "go1")
        #expect(shares.allSatisfy { !$0.isPaid })
        // Le prix reste figé même si le paiement est refusé.
        #expect(shares.allSatisfy { $0.finalPriceCents == $0.quantity * 990 })
    }

    @Test func belowMinimumCancelsAndNobodyPays() async throws {
        let repository = Self.repository(shares: [TierEngineTests.share("h1", 3), TierEngineTests.share("h2", 2)])
        let closure = try await repository.closeGroupOrder(id: "go1", trigger: Self.manual)

        #expect(closure.outcome == .cancelled)
        #expect(closure.order.status == .cancelled)
        #expect(closure.payments.isEmpty)
        let shares = try await repository.shares(ofGroupOrder: "go1")
        #expect(shares.allSatisfy { !$0.isPaid && $0.finalPriceCents == nil })
    }

    @Test func nonCoordinatorCannotClose() async throws {
        let repository = Self.repository()
        let member = GroupOrderClosureTrigger.manual(
            user: ClosurePolicyTests.user(household: "h2"),
            membership: ClosurePolicyTests.member("h2", role: .member)
        )
        await #expect(throws: AppError.invalidInput(ClosurePolicy.notAllowedMessage)) {
            try await repository.closeGroupOrder(id: "go1", trigger: member)
        }
        #expect(try await repository.groupOrder(id: "go1").status == .reached)
        #expect(try await repository.shares(ofGroupOrder: "go1").allSatisfy { !$0.isPaid })
    }

    @Test func vendorOfTheLotCanClose() async throws {
        let repository = Self.repository()
        let vendor = GroupOrderClosureTrigger.manual(
            user: ClosurePolicyTests.user(household: nil, vendor: Self.offer.vendorId), membership: nil
        )
        let closure = try await repository.closeGroupOrder(id: "go1", trigger: vendor)
        #expect(closure.order.status == .closed)
    }

    @Test func closingTwiceThrowsOrderClosedWithoutPayingAgain() async throws {
        let repository = Self.repository()
        try await repository.closeGroupOrder(id: "go1", trigger: Self.manual)
        await #expect(throws: AppError.orderClosed) {
            try await repository.closeGroupOrder(id: "go1", trigger: Self.manual)
        }
        await #expect(throws: AppError.orderClosed) {
            try await repository.closeGroupOrder(id: "go1", trigger: .automatic)
        }
    }

    @Test func automaticClosureOnlyAfterTheDeadline() async throws {
        let early = Self.repository(now: Self.before)
        await #expect(throws: AppError.self) {
            try await early.closeGroupOrder(id: "go1", trigger: .automatic)
        }
        #expect(try await early.groupOrder(id: "go1").status == .reached)

        let late = Self.repository(now: Self.after)
        let closure = try await late.closeGroupOrder(id: "go1", trigger: .automatic)
        #expect(closure.order.status == .closed)
        #expect(closure.paidCount == 3)
    }

    @Test func demoLaunchArgumentDeclinesPayments() {
        #expect(PaymentSimulator.fromLaunchArguments(["app", "-demoPaymentDeclined"]).outcome == .declined)
        #expect(PaymentSimulator.fromLaunchArguments(["app", "-useFakeData"]).outcome == .success)
    }

    // MARK: Écran du lot

    @MainActor
    @Test func offerDetailClosesAnOrderPastItsDeadlineOnLoad() async throws {
        let data = FakeData.montreal
        let lateNow = Date.now.addingTimeInterval(400 * 86_400)
        let repositories = AppRepositories.fake(behavior: .instant, data: data)
        let order = try #require(data.groupOrders.first { $0.id == FakeData.ID.potatoOrder })
        let offer = try #require(data.offers.first { $0.id == order.offerId })
        #expect(lateNow > offer.deadline)
        let late = AppRepositories(
            users: repositories.users, groups: repositories.groups, vendors: repositories.vendors,
            offers: repositories.offers,
            groupOrders: FakeGroupOrderRepository(
                groupOrders: data.groupOrders, shares: data.shares, offers: data.offers, now: { lateNow }
            ),
            pickupPoints: repositories.pickupPoints
        )
        let model = OfferDetailViewModel(
            repositories: late, offerId: offer.id, householdId: FakeData.ID.aminaHousehold,
            groupId: order.groupId, userId: FakeData.ID.amina, now: { lateNow }
        )
        await model.load()
        #expect(model.state.value?.groupOrder?.status != .open)
        #expect(model.state.value?.groupOrder?.status != .reached)
        #expect(model.state.value?.canClose == false)
    }

    @MainActor
    @Test func coordinatorClosesFromTheOfferScreen() async throws {
        let data = FakeData.montreal
        let repositories = AppRepositories.fake(behavior: .instant, data: data)
        let order = try #require(data.groupOrders.first { $0.id == FakeData.ID.potatoOrder })
        let model = OfferDetailViewModel(
            repositories: repositories, offerId: order.offerId, householdId: FakeData.ID.aminaHousehold,
            groupId: order.groupId, userId: FakeData.ID.amina
        )
        await model.load()
        #expect(model.state.value?.canClose == true)
        await model.closeOrder()
        #expect(model.actionError == nil)
        #expect(model.state.value?.groupOrder.map(TierEngine.isOpen) == false)
        #expect(model.state.value?.canClose == false)
        #expect(model.lastClosure != nil)
    }
}
