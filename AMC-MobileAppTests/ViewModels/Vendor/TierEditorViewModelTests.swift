import Foundation
import Testing
@testable import AMC_MobileApp

/// V2 Éditeur de paliers (T-022).
@MainActor
struct TierEditorViewModelTests {
    private typealias ID = FakeData.ID
    private typealias Draft = TierEditorViewModel.TierDraft

    private let now = Date.now

    /// Éditeur valide, sans chargement (produit posé directement).
    private func validEditor(_ repos: AppRepositories = .fake(behavior: .instant)) -> TierEditorViewModel {
        let fixedNow = now
        let model = TierEditorViewModel(repositories: repos, vendorId: ID.fermeRive, now: { fixedNow })
        model.productId = ID.potatoes
        model.shareUnit = "sac de 10 kg"
        model.totalShares = 40
        model.deadline = now.addingTimeInterval(86_400)
        model.tiers = [Draft(minShares: 10, priceCents: 1_150), Draft(minShares: 20, priceCents: 990),
                       Draft(minShares: 30, priceCents: 850)]
        return model
    }

    private func expectInvalid(_ model: TierEditorViewModel, _ message: String) {
        #expect(model.validationError == .invalidInput(message))
        #expect(!model.isValid)
    }

    // MARK: Chargement

    @Test func createModeLoadsProductsAndDefaults() async {
        let model = TierEditorViewModel(repositories: .fake(behavior: .instant), vendorId: ID.fermeRive)
        #expect(model.mode == .create)
        #expect(!model.isEditing)
        await model.load()
        #expect(model.loadState.error == nil)
        #expect(model.products.map(\.id) == [ID.apples, ID.potatoes])
        #expect(model.productId == ID.apples)
        #expect(model.shareUnit == "caisse de 5 kg")
        #expect(model.zones == ["f25d", "f25e"])
        #expect(model.referenceGroceryPriceCents == 1_499)
    }

    @Test func editModeLoadsTheOffer() async {
        let model = TierEditorViewModel(repositories: .fake(behavior: .instant), vendorId: ID.fermeRive, offerId: ID.potatoOffer)
        await model.load()
        #expect(model.isEditing)
        #expect(model.productId == ID.potatoes)
        #expect(model.totalShares == 40)
        #expect(model.shareUnit == "sac de 10 kg")
        #expect(model.tiers.map(\.minShares) == [10, 20, 30])
        #expect(model.tiers.map(\.priceCents) == [1_150, 990, 850])
        #expect(model.isValid)
    }

    @Test func editingAnotherVendorsOfferIsDenied() async {
        let model = TierEditorViewModel(repositories: .fake(behavior: .instant), vendorId: ID.fermeRive, offerId: ID.riceOffer)
        await model.load()
        #expect(model.loadState.error == .permissionDenied)
    }

    @Test func offlineLoadFails() async {
        let model = TierEditorViewModel(repositories: .fake(behavior: .failing(.offline)), vendorId: ID.fermeRive)
        await model.load()
        #expect(model.loadState.error == .offline)
    }

    // MARK: Sauvegarde

    @Test func createSavesAndReadsBack() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let model = validEditor(repos)
        let saved = try #require(await model.save())

        let reread = try await repos.offers.offer(id: saved.id)
        #expect(reread == saved)
        #expect(reread.vendorId == ID.fermeRive)
        #expect(reread.status == .active)
        #expect(reread.minimumSharesToLaunch == 10)
        #expect(reread.tiers == [PriceTier(minShares: 10, priceCents: 1_150), PriceTier(minShares: 20, priceCents: 990),
                                 PriceTier(minShares: 30, priceCents: 850)])
        #expect(model.saveState.value == saved)
        #expect(model.mode == .edit(offerId: saved.id))

        // Une deuxième sauvegarde met à jour le même lot.
        model.tiers[2].priceCents = 800
        let updated = try #require(await model.save())
        #expect(updated.id == saved.id)
        #expect(try await repos.offers.offers(ofVendor: ID.fermeRive).count == 3)
    }

    @Test func editSavesAndReadsBack() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let model = TierEditorViewModel(repositories: repos, vendorId: ID.fermeRive, offerId: ID.potatoOffer)
        await model.load()
        model.tiers[1].price = Decimal(string: "9.50")!
        #expect(model.tiers[1].priceCents == 950)
        _ = try #require(await model.save())

        let reread = try await repos.offers.offer(id: ID.potatoOffer)
        #expect(reread.sortedTiers.map(\.priceCents) == [1_150, 950, 850])
        #expect(reread.zones == ["f25d", "f25e"])
        #expect(try await repos.offers.offers(ofVendor: ID.fermeRive).count == 2)
    }

    @Test func invalidSaveDoesNotWrite() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let model = validEditor(repos)
        model.tiers = []
        #expect(await model.save() == nil)
        #expect(model.saveState == .failed(.invalidInput("Ajoute au moins un palier de prix.")))
        #expect(try await repos.offers.offers(ofVendor: ID.fermeRive).count == 2)
    }

    @Test func offlineSaveFails() async {
        var repos = AppRepositories.fake(behavior: .instant)
        repos.offers = FakeOfferRepository(behavior: .failing(.offline))
        let model = validEditor(repos)
        #expect(await model.save() == nil)
        #expect(model.saveState == .failed(.offline))
        #expect(model.mode == .create)
    }

    // MARK: Validation

    @Test func validDraftPasses() {
        let model = validEditor()
        #expect(model.validationError == nil)
        #expect(model.isValid)
        let single = validEditor()
        single.tiers = [Draft(minShares: 40, priceCents: 1)]
        #expect(single.isValid)
    }

    @Test func requiresAProduct() {
        let model = validEditor()
        model.productId = nil
        expectInvalid(model, "Choisis un produit pour ce lot.")
    }

    @Test func requiresAtLeastOneShare() {
        let model = validEditor()
        model.totalShares = 0
        expectInvalid(model, "Le lot doit contenir au moins une part.")
    }

    @Test func requiresAShareUnit() {
        let model = validEditor()
        model.shareUnit = "   "
        expectInvalid(model, "Indique ce que contient une part (par exemple « sac de 10 kg »).")
    }

    @Test func requiresAtLeastOneTier() {
        let model = validEditor()
        model.tiers = []
        expectInvalid(model, "Ajoute au moins un palier de prix.")
    }

    @Test func thresholdMustBePositive() {
        let model = validEditor()
        model.tiers[0].minShares = 0
        expectInvalid(model, "Le seuil du palier 1 doit être d'au moins 1 part.")
    }

    @Test func priceMustBePositive() {
        let model = validEditor()
        model.tiers[2].priceCents = 0
        expectInvalid(model, "Le prix du palier 3 doit être supérieur à 0 $.")
    }

    @Test func thresholdCannotExceedTotalShares() {
        let model = validEditor()
        model.tiers[2].minShares = 41
        expectInvalid(model, "Le seuil du palier 3 (41 parts) dépasse le total du lot (40 parts).")
        model.tiers[2].minShares = 40
        #expect(model.isValid)
    }

    @Test func thresholdsMustStrictlyIncrease() {
        let model = validEditor()
        model.tiers[1].minShares = 10
        expectInvalid(model, "Le seuil du palier 2 doit être plus grand que celui du palier 1 (10 parts).")
        model.tiers[1].minShares = 5
        expectInvalid(model, "Le seuil du palier 2 doit être plus grand que celui du palier 1 (10 parts).")
    }

    @Test func pricesMustStrictlyDecrease() {
        let model = validEditor()
        model.tiers[2].priceCents = 990
        expectInvalid(model, "Le prix du palier 3 doit être plus bas que celui du palier 2 (\(Money.format(990))).")
        model.tiers[2].priceCents = 1_000
        expectInvalid(model, "Le prix du palier 3 doit être plus bas que celui du palier 2 (\(Money.format(990))).")
    }

    @Test func deadlineMustBeInTheFuture() {
        let model = validEditor()
        model.deadline = now
        expectInvalid(model, "La date limite doit être dans le futur.")
        model.deadline = now.addingTimeInterval(-60)
        expectInvalid(model, "La date limite doit être dans le futur.")
    }

    // MARK: Aperçu et paliers

    @Test func previewComparesWithTheGroceryPrice() async {
        let model = TierEditorViewModel(repositories: .fake(behavior: .instant), vendorId: ID.fermeRive, offerId: ID.potatoOffer)
        await model.load()
        #expect(model.referenceGroceryPriceCents == 1_599)
        let previews = model.tierPreviews
        #expect(previews.map(\.rank) == [1, 2, 3])
        #expect(previews.map(\.minShares) == [10, 20, 30])
        #expect(previews.map(\.maxShares) == [19, 29, nil])
        #expect(previews.map(\.savingsPercent) == [28, 38, 47])
        #expect(previews.map(\.savingsPerShareCents) == [449, 609, 749])
        #expect(model.estimatedRevenueRangeCents == (40 * 850)...(40 * 1_150))
    }

    @Test func previewWithoutProductHasNoSavings() {
        let model = validEditor()
        #expect(model.referenceGroceryPriceCents == nil)
        #expect(model.tierPreviews.allSatisfy { $0.savingsPercent == 0 && $0.savingsPerShareCents == 0 })
    }

    @Test func addAndRemoveTiers() {
        let model = validEditor()
        model.tiers = [Draft(minShares: 10, priceCents: 1_000)]
        model.addTier()
        #expect(model.tiers.map(\.minShares) == [10, 20])
        #expect(model.tiers.map(\.priceCents) == [1_000, 900])
        model.totalShares = 25
        model.addTier()
        #expect(model.tiers.last?.minShares == 25)
        model.removeTier(id: model.tiers[1].id)
        #expect(model.tiers.map(\.minShares) == [10, 25])
        model.removeTiers(atOffsets: IndexSet([0, 1]))
        #expect(model.tiers.isEmpty)
        model.addTier()
        #expect(model.tiers.count == 1)
    }
}
