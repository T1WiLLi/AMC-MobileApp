import Foundation
import Testing
@testable import AMC_MobileApp

/// T-187 : une famille consulte la fiche publique d'un autre groupe : avis en lecture seule, tous les lots,
/// fiche d'un lot sans réservation. `VisitorGroupOrders` refuse toute lecture ou écriture de part,
/// comme `firestore.rules` pour un ménage qui n'est pas membre du groupe.
@MainActor
struct GroupPublicConsultationTests {
    private typealias ID = FakeData.ID
    private static let visitor = "household-visiteur"

    private func visitorRepositories() -> AppRepositories {
        var repositories = AppRepositories.fake(behavior: .instant)
        repositories.groupOrders = VisitorGroupOrders(base: repositories.groupOrders)
        return repositories
    }

    // MARK: Fiche d'un lot en consultation

    @Test func consultationShowsTheVisitedGroupOrderWithoutReadingShares() async throws {
        let model = OfferDetailViewModel(repositories: visitorRepositories(), offerId: ID.potatoOffer,
                                         householdId: Self.visitor, groupId: ID.saintMichel, isReadOnly: true)
        await model.load()

        // Lire une part lèverait « Action non permise » : la fiche se charge quand même.
        let content = try #require(model.state.value)
        #expect(content.product.id == ID.potatoes)
        #expect(content.vendor.id == ID.fermeRive)
        #expect(content.committedShares == 19)
        #expect(content.myShareQuantity == 0)
        #expect(!content.canStartOrder)
        #expect(model.pricing?.currentPriceCents == 1_150)
        #expect(!model.canReserve)
    }

    @Test func visitorCannotReserveEvenByCallingTheAction() async throws {
        let repositories = visitorRepositories()
        let model = OfferDetailViewModel(repositories: repositories, offerId: ID.potatoOffer,
                                         householdId: Self.visitor, groupId: ID.saintMichel, isReadOnly: true)
        await model.load()
        model.selectedQuantity = 2
        await model.reserve()

        #expect(model.actionError == .invalidInput(String(localized: "Rejoins ce groupe pour réserver ta part.")))
        #expect(model.celebration == nil)
        #expect(model.state.value?.committedShares == 19)
        let order = try #require(try await repositories.groupOrders.groupOrders(ofGroup: ID.saintMichel)
            .first { $0.offerId == ID.potatoOffer })
        #expect(order.committedShares == 19)
    }

    @Test func consultationNeverOpensAnOrderForALotTheGroupHasNotStarted() async throws {
        let repositories = visitorRepositories()
        let orders = try await repositories.groupOrders.groupOrders(ofGroup: ID.hochelaga)
        let offers = try await repositories.offers.activeOffers(inZone: nil)
        let notStarted = try #require(offers.first { offer in !orders.contains { $0.offerId == offer.id } })

        let model = OfferDetailViewModel(repositories: repositories, offerId: notStarted.id,
                                         householdId: Self.visitor, groupId: ID.hochelaga, isReadOnly: true)
        await model.load()
        let content = try #require(model.state.value)
        #expect(content.groupOrder == nil)
        #expect(!content.canStartOrder)
        #expect(!content.isOpen)
        #expect(!model.canReserve)
    }

    @Test func memberModeIsUnchanged() async throws {
        let model = OfferDetailViewModel(repositories: .fake(behavior: .instant), offerId: ID.potatoOffer,
                                         householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await model.load()
        #expect(!model.isReadOnly)
        #expect(model.canReserve)
    }

    @Test func consultationEndsOnceTheHouseholdIsAMember() {
        #expect(OfferConsultation.isActive(isMember: nil))
        #expect(OfferConsultation.isActive(isMember: false))
        #expect(!OfferConsultation.isActive(isMember: true))
    }

    @Test func joiningFromTheLotEndsTheConsultation() async throws {
        let group = GroupDetailViewModel(repositories: visitorRepositories(), householdId: Self.visitor,
                                         groupId: ID.hochelaga)
        await group.load()
        let consultation = OfferConsultation(groupId: ID.hochelaga, groupModel: group)
        #expect(consultation.isActive)
        #expect(consultation.group?.id == ID.hochelaga)

        await group.join()
        #expect(group.actionError == nil)
        #expect(!consultation.isActive)
    }

    // MARK: Avis en lecture seule

    @Test func visitorReadsReviewsWithoutRating() async throws {
        let ratings = GroupRatingsViewModel(repositories: visitorRepositories(), groupId: ID.hochelaga,
                                            householdId: Self.visitor, userId: nil, isReadOnly: true)
        await ratings.load(isMember: false)
        let content = try #require(ratings.state.value)
        #expect(content.summary.count == 3)
        #expect(content.summary.average != nil)
        #expect(!content.recent.isEmpty)
        #expect(content.eligibility == .notEligible)
        #expect(!content.eligibility.canRate)

        if case .failure(let error) = await ratings.save(rating: 5, comment: "") {
            #expect(error == .permissionDenied)
        } else {
            Issue.record("Un visiteur ne doit pas pouvoir noter depuis la fiche publique.")
        }
    }

    @Test func readOnlyHidesRatingForEveryoneButKeepsTheOwnerNote() {
        typealias Model = GroupRatingsViewModel
        #expect(Model.displayedEligibility(.member, isReadOnly: true) == .notEligible)
        #expect(Model.displayedEligibility(.alreadyRated, isReadOnly: true) == .notEligible)
        #expect(Model.displayedEligibility(.formerMember(groupOrderId: "o1"), isReadOnly: true) == .notEligible)
        #expect(Model.displayedEligibility(.owner, isReadOnly: true) == .owner)
        #expect(Model.displayedEligibility(.member, isReadOnly: false) == .member)
        #expect(Model.displayedEligibility(.formerMember(groupOrderId: "o1"), isReadOnly: false)
                == .formerMember(groupOrderId: "o1"))
    }
}

/// Doublure : un ménage visiteur ne lit ni n'écrit aucune part, et n'ouvre aucune commande (comme `firestore.rules`).
private struct VisitorGroupOrders: GroupOrderRepository {
    let base: any GroupOrderRepository

    func groupOrders(ofGroup groupId: String) async throws -> [GroupOrder] { try await base.groupOrders(ofGroup: groupId) }
    func groupOrders(ofOffer offerId: String) async throws -> [GroupOrder] { try await base.groupOrders(ofOffer: offerId) }
    func openGroupOrder(groupId: String, offerId: String) async throws -> GroupOrder { throw AppError.permissionDenied }
    func groupOrder(id: String) async throws -> GroupOrder { try await base.groupOrder(id: id) }
    func shares(ofGroupOrder groupOrderId: String) async throws -> [Share] { throw AppError.permissionDenied }
    func share(ofHousehold householdId: String, inGroupOrder groupOrderId: String) async throws -> Share? {
        throw AppError.permissionDenied
    }
    func setShare(quantity: Int, householdId: String, groupOrderId: String) async throws -> GroupOrder {
        throw AppError.permissionDenied
    }
    func observeGroupOrder(id: String) async -> AsyncThrowingStream<GroupOrder, any Error> {
        await base.observeGroupOrder(id: id)
    }
    func setPickupPoint(_ pickupPointId: String?, slots: [PickupSlot], groupOrderId: String) async throws -> GroupOrder {
        throw AppError.permissionDenied
    }
    func reservePickupSlot(start: Date?, householdId: String, groupOrderId: String) async throws -> Share {
        throw AppError.permissionDenied
    }
}
