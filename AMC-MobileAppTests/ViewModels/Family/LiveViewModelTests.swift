import Foundation
import Testing
@testable import AMC_MobileApp

/// Temps réel côté ViewModels (T-096, S-05) : un « second client » écrit dans le même dépôt fake,
/// l'écran observé se met à jour sans recharger.
/// Pommes de terre à Saint-Michel : 19 parts (voisin-2 en a 1), paliers 10 → 11,50 $, 20 → 9,90 $, 30 → 8,50 $.
@MainActor
struct LiveViewModelTests {
    private typealias ID = FakeData.ID
    private let neighbor2 = "household-voisin-2"
    private let neighbor3 = "household-voisin-3"

    /// Attente bornée et déterministe : rend la main tant que la condition est fausse (2 s au plus).
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            if ContinuousClock.now >= deadline { return false }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
    }

    /// Laisse tourner les tâches en attente quelques fois (pour vérifier qu'il ne se passe RIEN).
    private func settle() async {
        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    private func offerDetail(_ repos: AppRepositories) async -> OfferDetailViewModel {
        let viewModel = OfferDetailViewModel(repositories: repos, offerId: ID.potatoOffer,
                                             householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await viewModel.load()
        return viewModel
    }

    // MARK: Fiche du lot

    @Test func offerDetailFollowsAnotherHouseholdsShare() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let viewModel = await offerDetail(repos)
        let task = Task { await viewModel.observe() }
        defer { task.cancel() }
        #expect(await waitUntil { viewModel.isLive })

        try await repos.groupOrders.setShare(quantity: 0, householdId: neighbor2, groupOrderId: ID.potatoOrder)

        #expect(await waitUntil { viewModel.state.value?.committedShares == 18 })
        #expect(viewModel.pricing?.currentPriceCents == 1_150)
        #expect(viewModel.state.value?.groupOrder?.committedHouseholds == 10)
        #expect(viewModel.tierUnlockCount == 0)
    }

    @Test func tierCrossedByAnotherFamilyFiresOnce() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let viewModel = await offerDetail(repos)
        let task = Task { await viewModel.observe() }
        defer { task.cancel() }
        #expect(await waitUntil { viewModel.isLive })

        // 19 → 20 : palier 2 (9,90 $).
        try await repos.groupOrders.setShare(quantity: 2, householdId: neighbor2, groupOrderId: ID.potatoOrder)
        #expect(await waitUntil { viewModel.tierUnlockCount == 1 })
        #expect(viewModel.lastUnlockedTierNumber == 2)
        #expect(viewModel.pricing?.currentPriceCents == 990)
        let unlock = try #require(viewModel.liveUnlock)
        #expect(unlock.tierNumber == 2)
        #expect(unlock.previousPriceCents == 1_150)
        #expect(unlock.newPriceCents == 990)
        #expect(unlock.committedShares == 20)
        #expect(viewModel.celebration == nil)

        // 20 → 21 : même palier, pas de nouvelle célébration.
        try await repos.groupOrders.setShare(quantity: 4, householdId: neighbor3, groupOrderId: ID.potatoOrder)
        #expect(await waitUntil { viewModel.state.value?.committedShares == 21 })
        await settle()
        #expect(viewModel.tierUnlockCount == 1)

        viewModel.dismissLiveUnlock()
        #expect(viewModel.liveUnlock == nil)
        #expect(viewModel.lastUnlockedTierNumber == 2)
    }

    @Test func firstEmissionNeverCelebrates() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let viewModel = await offerDetail(repos)
        // Un voisin franchit le palier entre le chargement et le début de l'écoute : c'est l'état de départ.
        try await repos.groupOrders.setShare(quantity: 2, householdId: neighbor2, groupOrderId: ID.potatoOrder)
        let task = Task { await viewModel.observe() }
        defer { task.cancel() }

        #expect(await waitUntil { viewModel.state.value?.committedShares == 20 })
        await settle()
        #expect(viewModel.isLive)
        #expect(viewModel.tierUnlockCount == 0)
        #expect(viewModel.liveUnlock == nil)
    }

    @Test func ownReservationUsesCelebrationNotLiveUnlock() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let viewModel = await offerDetail(repos)
        let task = Task { await viewModel.observe() }
        defer { task.cancel() }
        #expect(await waitUntil { viewModel.isLive })

        viewModel.selectedQuantity = 1
        await viewModel.reserve()
        await settle()

        #expect(viewModel.celebration?.tierNumber == 2)
        #expect(viewModel.tierUnlockCount == 0)
        #expect(viewModel.state.value?.committedShares == 20)
    }

    @Test func cancellingTheTaskStopsListening() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let viewModel = await offerDetail(repos)
        let task = Task { await viewModel.observe() }
        #expect(await waitUntil { viewModel.isLive })

        task.cancel()
        await task.value
        #expect(!viewModel.isLive)

        try await repos.groupOrders.setShare(quantity: 2, householdId: neighbor2, groupOrderId: ID.potatoOrder)
        await settle()
        #expect(viewModel.state.value?.committedShares == 19)
        #expect(viewModel.tierUnlockCount == 0)
    }

    @Test func observationErrorKeepsLoadedData() async throws {
        let viewModel = await offerDetail(AppRepositories.fake(behavior: .instant))
        #expect(viewModel.state.value?.committedShares == 19)

        // L'écoute coupe tout de suite (réseau perdu).
        await viewModel.follow(AsyncThrowingStream { $0.finish(throwing: AppError.offline) })

        #expect(!viewModel.isLive)
        #expect(viewModel.state.value?.committedShares == 19)
        #expect(viewModel.actionError == nil)
    }

    // MARK: Fiche du groupe

    @Test func groupDetailFollowsMembersAndOpenOrders() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let viewModel = GroupDetailViewModel(repositories: repos, householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await viewModel.load()
        let membersBefore = try #require(viewModel.state.value?.members.count)
        let task = Task { await viewModel.observe() }
        defer { task.cancel() }
        #expect(await waitUntil { viewModel.isLive })

        try await repos.groups.join(groupId: ID.saintMichel, householdId: "household-nouveau")
        #expect(await waitUntil { viewModel.state.value?.members.count == membersBefore + 1 })
        #expect(viewModel.state.value?.isMember == true)

        try await repos.groupOrders.setShare(quantity: 2, householdId: neighbor2, groupOrderId: ID.potatoOrder)
        #expect(await waitUntil {
            viewModel.state.value?.openOrders.first { $0.offer.id == ID.potatoOffer }?.committedShares == 20
        })
        #expect(viewModel.state.value?.openOrders.first { $0.offer.id == ID.potatoOffer }?.pricing.currentPriceCents == 990)
    }

    @Test func groupDetailStopsListeningWhenCancelled() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let viewModel = GroupDetailViewModel(repositories: repos, householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await viewModel.load()
        let membersBefore = viewModel.state.value?.members.count
        let task = Task { await viewModel.observe() }
        #expect(await waitUntil { viewModel.isLive })
        task.cancel()
        await task.value
        #expect(!viewModel.isLive)

        try await repos.groups.join(groupId: ID.saintMichel, householdId: "household-nouveau")
        await settle()
        #expect(viewModel.state.value?.members.count == membersBefore)
    }

    // MARK: Panier

    @Test func cartRepricesLinesLive() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        try await repos.groupOrders.setShare(quantity: 1, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        let viewModel = CartViewModel(repositories: repos, householdId: ID.aminaHousehold)
        await viewModel.load()
        #expect(viewModel.lines.first?.unitPriceCents == 990)
        let task = Task { await viewModel.observe() }
        defer { task.cancel() }
        #expect(await waitUntil { viewModel.isLive })

        // 20 → 30 : palier 3 (8,50 $).
        try await repos.groupOrders.setShare(quantity: 11, householdId: neighbor2, groupOrderId: ID.potatoOrder)
        #expect(await waitUntil { viewModel.lines.first?.unitPriceCents == 850 })
        #expect(viewModel.state.value?.estimatedTotalCents == 850)
        #expect(viewModel.lines.first?.quantity == 1)
    }
}
