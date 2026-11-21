import Foundation
import Testing
@testable import AMC_MobileApp

/// Gestion des lots du vendeur (T-064, RQ-036, RQ-037).
@MainActor
struct VendorOffersViewModelTests {
    private typealias ID = FakeData.ID
    private typealias Kind = VendorOffersViewModel.SectionKind

    private let now = Date.now
    private let day: TimeInterval = 86_400

    /// Montréal + un lot terminé, un brouillon et un lot actif dont une commande est confirmée.
    private func richData() -> FakeData {
        var data = FakeData.montreal
        let template = data.offers.first { $0.id == ID.appleOffer }!
        var closed = template
        closed.id = "offer-ancien"
        closed.status = .closed
        closed.deadline = now.addingTimeInterval(-10 * day)
        var draft = template
        draft.id = "offer-brouillon"
        draft.status = .draft
        draft.deadline = now.addingTimeInterval(9 * day)
        var expiredDraft = template
        expiredDraft.id = "offer-brouillon-expire"
        expiredDraft.status = .draft
        expiredDraft.deadline = now.addingTimeInterval(-1 * day)
        data.offers += [closed, draft, expiredDraft]
        data.groupOrders += [
            VendorTestData.order(id: "order-hochelaga-pommes", group: ID.hochelaga, offer: ID.appleOffer,
                                 shares: 7, households: 4, tierIndex: 0, status: .closed),
            VendorTestData.order(id: "order-annulee", group: ID.hochelaga, offer: ID.potatoOffer,
                                 shares: 50, households: 9, tierIndex: nil, status: .cancelled),
        ]
        return data
    }

    private func model(_ repos: AppRepositories) -> VendorOffersViewModel {
        let fixedNow = now
        return VendorOffersViewModel(repositories: repos, vendorId: ID.fermeRive, now: { fixedNow })
    }

    // MARK: Sections

    @Test func groupsOffersBySection() async throws {
        let model = model(.fake(behavior: .instant, data: richData()))
        await model.load()
        #expect(model.state.error == nil)
        #expect(model.sections.map(\.kind) == [.active, .paused, .ended])
        #expect(model.sections.map(\.title) == ["Actifs", "En pause et brouillons", "Terminés et retirés"])

        let active = try #require(model.section(.active))
        #expect(active.rows.map(\.id) == [ID.potatoOffer, ID.appleOffer])
        let potato = active.rows[0]
        #expect(potato.productName == "Pommes de terre jaunes")
        #expect(potato.committedShares == 19) // la commande annulée ne compte pas
        #expect(potato.liveOrderCount == 1)
        #expect(potato.confirmedOrderCount == 0)
        #expect(active.rows[1].committedShares == 7)
        #expect(active.rows[1].confirmedOrderCount == 1)

        #expect(model.section(.paused)?.rows.map(\.id) == ["offer-brouillon-expire", "offer-brouillon"])
        #expect(model.section(.ended)?.rows.map(\.id) == ["offer-ancien"])
        // Le riz appartient à un autre vendeur.
        #expect(model.row(offerId: ID.riceOffer) == nil)
    }

    @Test func emptyWhenTheVendorHasNoOffers() async {
        var data = FakeData.montreal
        data.offers.removeAll { $0.vendorId == ID.fermeRive }
        let model = model(.fake(behavior: .instant, data: data))
        await model.load()
        #expect(model.state == .empty)
        #expect(model.sections.isEmpty)
    }

    @Test func failingRepositoryFails() async {
        let model = model(.fake(behavior: .failing(.offline)))
        await model.load()
        #expect(model.state.error == .offline)
    }

    // MARK: Pause et reprise

    @Test func pauseThenResume() async throws {
        let repos = AppRepositories.fake(behavior: .instant, data: richData())
        let model = model(repos)
        await model.load()
        #expect(model.canPause(try #require(model.row(offerId: ID.potatoOffer))))

        await model.pause(offerId: ID.potatoOffer)
        #expect(model.actionError == nil)
        #expect(try await repos.offers.offer(id: ID.potatoOffer).status == .draft)
        #expect(model.section(.paused)?.rows.map(\.id).contains(ID.potatoOffer) == true)
        #expect(model.section(.active)?.rows.map(\.id) == [ID.appleOffer])
        #expect(try await repos.offers.activeOffers(inZone: nil).map(\.id).contains(ID.potatoOffer) == false)

        await model.resume(offerId: ID.potatoOffer)
        #expect(model.actionError == nil)
        #expect(try await repos.offers.offer(id: ID.potatoOffer).status == .active)
        #expect(model.section(.active)?.rows.map(\.id) == [ID.potatoOffer, ID.appleOffer])
    }

    @Test func pauseAndResumeRules() async throws {
        let repos = AppRepositories.fake(behavior: .instant, data: richData())
        let model = model(repos)
        await model.load()

        await model.pause(offerId: "offer-ancien")
        #expect(model.actionError == .invalidInput("Seul un lot actif peut être mis en pause."))

        await model.resume(offerId: ID.appleOffer)
        #expect(model.actionError == .invalidInput("Seul un lot en pause ou un brouillon peut être republié."))

        let expired = try #require(model.row(offerId: "offer-brouillon-expire"))
        #expect(!model.canResume(expired))
        await model.resume(offerId: expired.id)
        #expect(model.actionError == .invalidInput("La date limite de ce lot est passée : change-la avant de le republier."))
        #expect(try await repos.offers.offer(id: expired.id).status == .draft)

        await model.pause(offerId: ID.riceOffer)
        #expect(model.actionError == .notFound)
    }

    @Test func cannotPauseAfterTheDeadline() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let late = now.addingTimeInterval(3 * day) // après la date limite des pommes de terre (+2 j)
        let model = VendorOffersViewModel(repositories: repos, vendorId: ID.fermeRive, now: { late })
        await model.load()
        await model.pause(offerId: ID.potatoOffer)
        #expect(model.actionError == .invalidInput("La date limite de ce lot est passée : il ne peut plus être mis en pause."))
        #expect(try await repos.offers.offer(id: ID.potatoOffer).status == .active)
    }

    // MARK: Retrait

    @Test func withdrawMovesTheOfferToEnded() async throws {
        let repos = AppRepositories.fake(behavior: .instant, data: richData())
        let model = model(repos)
        await model.load()
        await model.withdraw(offerId: ID.potatoOffer)
        #expect(model.actionError == nil)
        #expect(try await repos.offers.offer(id: ID.potatoOffer).status == .cancelled)
        #expect(model.section(.ended)?.rows.map(\.id).contains(ID.potatoOffer) == true)

        await model.withdraw(offerId: "offer-brouillon")
        #expect(model.actionError == nil)
        #expect(try await repos.offers.offer(id: "offer-brouillon").status == .cancelled)
    }

    @Test func withdrawRules() async throws {
        let repos = AppRepositories.fake(behavior: .instant, data: richData())
        let model = model(repos)
        await model.load()

        let apples = try #require(model.row(offerId: ID.appleOffer))
        #expect(!model.canWithdraw(apples))
        await model.withdraw(offerId: ID.appleOffer)
        #expect(model.actionError == .invalidInput("Des commandes de ce lot sont déjà confirmées : il ne peut plus être retiré."))
        #expect(try await repos.offers.offer(id: ID.appleOffer).status == .active)

        await model.withdraw(offerId: "offer-ancien")
        #expect(model.actionError == .invalidInput("Ce lot est déjà terminé ou retiré."))
    }

    // MARK: Duplication

    @Test func duplicateCreatesADraftOneWeekLater() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let model = model(repos)
        await model.load()
        let source = try await repos.offers.offer(id: ID.potatoOffer)

        let copy = try #require(await model.duplicate(offerId: ID.potatoOffer))
        #expect(model.actionError == nil)
        #expect(copy.id != source.id)
        #expect(copy.id.hasPrefix("offer-"))
        #expect(copy.status == .draft)
        #expect(copy.tiers == source.tiers)
        #expect(copy.totalShares == source.totalShares)
        #expect(copy.productId == source.productId)
        #expect(copy.zones == source.zones)
        #expect(copy.deadline == source.deadline.addingTimeInterval(7 * day))
        #expect(model.lastDuplicatedOffer == copy)

        #expect(try await repos.offers.offer(id: copy.id) == copy)
        #expect(model.section(.paused)?.rows.map(\.id) == [copy.id])
        #expect(model.section(.paused)?.rows.first?.committedShares == 0)
        #expect(try await repos.offers.offer(id: ID.potatoOffer).status == .active)
    }

    @Test func duplicatingAnExpiredOfferStartsFromNow() async throws {
        let model = model(.fake(behavior: .instant, data: richData()))
        await model.load()
        let copy = try #require(await model.duplicate(offerId: "offer-ancien"))
        #expect(copy.deadline == now.addingTimeInterval(7 * day))
        #expect(copy.status == .draft)
    }

    @Test func failingActionSetsActionError() async {
        let model = model(.fake(behavior: .failing(.offline)))
        await model.load()
        #expect(await model.duplicate(offerId: ID.potatoOffer) == nil)
        #expect(model.actionError == .notFound) // rien n'a été chargé
        #expect(model.state.error == .offline)
    }
}
