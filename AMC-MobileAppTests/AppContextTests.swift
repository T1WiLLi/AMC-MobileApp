import Testing
@testable import AMC_MobileApp

@MainActor
struct AppContextTests {
    @Test func launchContextNeverUsesDemoIdsWithFirebase() {
        // T-127 : avec Firebase, le contexte de base n'a aucun id ; il est résolu depuis la session.
        for mode in [BackendMode.emulator, .demoProject] {
            let context = AppContext.launch(mode: mode)
            #expect(!context.isResolved)
            #expect(context.householdId.isEmpty && context.vendorId.isEmpty && context.groupId == nil)
        }
        #expect(AppContext.launch(mode: .fake).isResolved)
    }

    @Test func demoContextUsesFakePersonas() {
        let context = AppContext.demo
        #expect(context.householdId == FakeData.ID.aminaHousehold)
        #expect(context.groupId == FakeData.ID.saintMichel)
        #expect(context.vendorId == FakeData.ID.moulinsDuNord)
    }

    @Test func offerRouteIsHashableByOffer() {
        #expect(OfferRoute(offerId: "a") == OfferRoute(offerId: "a"))
        #expect(OfferRoute(offerId: "a") != OfferRoute(offerId: "b"))
    }
}
