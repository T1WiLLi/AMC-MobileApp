import Foundation
import Testing
@testable import AMC_MobileApp

/// T-181 : « + Panier suspendu » dans la réservation de la fiche lot.
@MainActor
struct SuspendedBasketReserveTests {
    private typealias ID = FakeData.ID

    private func makeModel(_ repos: AppRepositories = .fake(behavior: .instant)) -> OfferDetailViewModel {
        OfferDetailViewModel(repositories: repos, offerId: ID.potatoOffer,
                             householdId: ID.aminaHousehold, groupId: ID.saintMichel)
    }

    @Test func choicesAreFiveTenTwentyDollars() {
        #expect(OfferDetailViewModel.suspendedChoices == [500, 1_000, 2_000])
    }

    @Test func toggleSelectsThenClears() {
        let model = makeModel()
        model.toggleSuspended(500)
        #expect(model.suspendedCents == 500)
        model.toggleSuspended(1_000)
        #expect(model.suspendedCents == 1_000)
        model.toggleSuspended(1_000)
        #expect(model.suspendedCents == 0)
    }

    @Test func totalIncludesTheBasket() async {
        let model = makeModel()
        await model.load()
        let share = model.selectedTotalCents
        model.toggleSuspended(500)
        #expect(model.selectedTotalWithBasketCents == share + 500)
    }

    @Test func reserveSavesTheBasketWithTheShare() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let model = makeModel(repos)
        await model.load()
        model.toggleSuspended(1_000)
        await model.reserve()
        #expect(model.actionError == nil)
        let content = try #require(model.state.value)
        #expect(content.myShareQuantity == 1)
        #expect(content.mySuspendedCents == 1_000)
        let order = try #require(content.groupOrder)
        let share = try await repos.groupOrders.share(ofHousehold: ID.aminaHousehold, inGroupOrder: order.id)
        #expect(share?.suspendedAmountCents == 1_000)
    }

    @Test func changingOnlyTheBasketIsAllowedOnceReserved() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let model = makeModel(repos)
        await model.load()
        await model.reserve()
        #expect(!model.canReserve)
        model.toggleSuspended(2_000)
        #expect(model.canReserve)
        await model.reserve()
        #expect(model.state.value?.mySuspendedCents == 2_000)
        model.toggleSuspended(2_000)
        await model.reserve()
        #expect(model.state.value?.mySuspendedCents == 0)
    }

    @Test func ledgerSetsAbsoluteAmountWithinCap() throws {
        let data = FakeData.montreal
        let order = data.groupOrders[0]
        let share = try #require(data.shares[order.id]?.first)
        #expect(try SolidarityLedger.settingSuspendedBasket(500, on: share, in: order).suspendedAmountCents == 500)
        let again = try SolidarityLedger.settingSuspendedBasket(500, on: share, in: order)
        #expect(try SolidarityLedger.settingSuspendedBasket(1_000, on: again, in: order).suspendedAmountCents == 1_000)
        #expect(throws: AppError.self) { try SolidarityLedger.settingSuspendedBasket(20_001, on: share, in: order) }
        #expect(throws: AppError.self) { try SolidarityLedger.settingSuspendedBasket(-1, on: share, in: order) }
        var closed = order
        closed.status = .closed
        #expect(throws: AppError.self) { try SolidarityLedger.settingSuspendedBasket(500, on: share, in: closed) }
    }
}
