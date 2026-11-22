import Foundation
import Testing
@testable import AMC_MobileApp

/// Panier suspendu ajouté avant de valider sa part sur la fiche d'un lot (RQ-078), sur `FakeData.montreal`.
/// Pommes de terre à Saint-Michel : 19 parts, la part d'Amina fait tomber le palier à 9,90 $.
@MainActor
struct SuspendedBasketReservationTests {
    private typealias ID = FakeData.ID

    private func detail(_ repositories: AppRepositories) -> OfferDetailViewModel {
        OfferDetailViewModel(repositories: repositories, offerId: ID.potatoOffer,
                             householdId: ID.aminaHousehold, groupId: ID.saintMichel)
    }

    @Test func presetsOfferFiveDollarsInOneTap() {
        #expect(OfferDetailViewModel.suspendedBasketPresetsCents == [0, 500, 1_000])
    }

    @Test func totalIncludesTheSuspendedBasket() async throws {
        let viewModel = detail(.fake(behavior: .instant))
        await viewModel.load()
        #expect(viewModel.selectedTotalCents == 990)
        #expect(viewModel.selectedTotalWithBasketCents == 990)

        viewModel.suspendedBasketCents = 500
        #expect(viewModel.selectedTotalCents == 990)
        #expect(viewModel.selectedTotalWithBasketCents == 1_490)

        viewModel.selectedQuantity = 2
        #expect(viewModel.selectedTotalWithBasketCents == 2 * 990 + 500)
    }

    @Test func reservingRecordsTheBasketAndImpactCountsIt() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        let impact = ImpactViewModel(repositories: repositories, householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await impact.load()
        let before = try #require(impact.state.value)

        let viewModel = detail(repositories)
        await viewModel.load()
        viewModel.suspendedBasketCents = 500
        await viewModel.reserve()

        #expect(viewModel.actionError == nil)
        #expect(viewModel.state.value?.myShareQuantity == 1)
        #expect(viewModel.state.value?.myDonationCents == 500)
        #expect(viewModel.suspendedBasketCents == 0)
        #expect(viewModel.lastDonationCents == 500)
        #expect(viewModel.donationCount == 1)
        // Déjà offert : il reste dans le total à payer à la cueillette.
        #expect(viewModel.selectedTotalWithBasketCents == 990 + 500)
        #expect(!viewModel.canReserve)

        let share = try #require(try await repositories.groupOrders.share(ofHousehold: ID.aminaHousehold, inGroupOrder: ID.potatoOrder))
        #expect(share.quantity == 1)
        #expect(share.suspendedAmountCents == 500)

        await impact.load()
        let after = try #require(impact.state.value)
        #expect(after.suspendedBasketCount == before.suspendedBasketCount + 1)
        #expect(after.suspendedAmountCents == before.suspendedAmountCents + 500)
        #expect(ImpactSnapshot(content: after, firstName: "Amina", neighborhoodName: "Saint-Michel")
            .suspendedBasketsOffered == before.suspendedBasketCount + 1)
    }

    @Test func basketCanBeAddedToAnExistingShare() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        let viewModel = detail(repositories)
        await viewModel.load()
        await viewModel.reserve()
        viewModel.dismissCelebration()
        #expect(!viewModel.canReserve)

        viewModel.suspendedBasketCents = 1_000
        #expect(viewModel.canReserve)
        await viewModel.reserve()

        #expect(viewModel.actionError == nil)
        #expect(viewModel.state.value?.committedShares == 20)
        #expect(viewModel.state.value?.myDonationCents == 1_000)
        #expect(viewModel.celebration == nil)
        let share = try await repositories.groupOrders.share(ofHousehold: ID.aminaHousehold, inGroupOrder: ID.potatoOrder)
        #expect(share?.suspendedAmountCents == 1_000)
    }

    @Test func noBasketWithoutChoosingOne() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        let viewModel = detail(repositories)
        await viewModel.load()
        await viewModel.reserve()

        #expect(viewModel.donationCount == 0)
        #expect(viewModel.lastDonationCents == nil)
        let share = try await repositories.groupOrders.share(ofHousehold: ID.aminaHousehold, inGroupOrder: ID.potatoOrder)
        #expect(share?.suspendedAmountCents == 0)
    }

    @Test func fakeRepositoryRefusesABasketWithoutShare() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        await #expect(throws: AppError.notFound) {
            try await repositories.groupOrders.addSuspendedBasket(
                amountCents: 500, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder
            )
        }
    }
}
