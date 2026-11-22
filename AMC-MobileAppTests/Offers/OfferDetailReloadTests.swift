import Foundation
import Testing
@testable import AMC_MobileApp

/// T-199 (R-c) : la fiche d'un lot garde son contenu pendant un rechargement, pour que le `ScrollView`
/// ne revienne pas en haut (aucun passage par `.loading`).
@MainActor
struct OfferDetailReloadTests {
    private typealias ID = FakeData.ID

    @Test func reloadKeepsContentDisplayedAndStaysLoaded() async throws {
        let model = OfferDetailViewModel(repositories: .fake(behavior: .instant), offerId: ID.potatoOffer,
                                         householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await model.load()
        let first = try #require(model.state.value)
        await model.load()
        let second = try #require(model.state.value)
        #expect(second.offer.id == first.offer.id)
        #expect(second.groupOrder?.id == first.groupOrder?.id)
    }
}
