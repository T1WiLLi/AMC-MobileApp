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

    /// Le lot de pommes de terre en brouillon jamais publié : ses conditions restent modifiables.
    private func draftRepositories() -> AppRepositories {
        var data = FakeData.montreal
        if let index = data.offers.firstIndex(where: { $0.id == ID.potatoOffer }) {
            data.offers[index].status = .draft
            data.offers[index].wasPublished = false
        }
        return .fake(behavior: .instant, data: data)
    }

    @Test func totalCannotDropBelowSharesAlreadyReserved() async throws {
        let model = TierEditorViewModel(repositories: draftRepositories(), vendorId: ID.fermeRive, offerId: ID.potatoOffer)
        await model.load()
        let committed = model.committedShares
        try #require(committed > 0)
        model.totalShares = committed - 1
        model.tiers = [Draft(minShares: 1, priceCents: 1_150)]
        #expect(model.validationError != nil)
        model.totalShares = committed
        #expect(model.validationError == nil)
    }

    @Test func secondSaveWhileSavingIsIgnored() async throws {
        let repos = AppRepositories.fake(behavior: FakeBehavior(latencyMilliseconds: 150...150, failure: nil))
        let model = validEditor(repos)
        async let first = model.save()
        try await Task.sleep(for: .milliseconds(30))
        let second = await model.save()
        #expect(second == nil)
        let saved = await first
        #expect(saved != nil)
        let mine = try await repos.offers.offers(ofVendor: ID.fermeRive).filter { $0.productId == ID.potatoes }
        #expect(mine.count == 2) // le lot d'origine + un seul nouveau
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
        let repos = draftRepositories()
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

    // MARK: Sécurité : lot publié

    /// Lot actif : paliers, parts et part sont figés ; seuls la date limite et les zones partent à l'enregistrement.
    @Test func publishedOfferKeepsItsTermsWhenSaved() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let before = try await repos.offers.offer(id: ID.potatoOffer)
        let model = TierEditorViewModel(repositories: repos, vendorId: ID.fermeRive, offerId: ID.potatoOffer)
        await model.load()
        #expect(model.areTermsLocked)
        model.tiers[0].priceCents = 99_999
        model.totalShares = before.totalShares + 10
        model.shareUnit = "sac de 1 kg"
        let later = before.deadline.addingTimeInterval(86_400)
        model.deadline = later
        #expect(model.isValid)
        _ = try #require(await model.save())

        let reread = try await repos.offers.offer(id: ID.potatoOffer)
        #expect(reread.hasSameTerms(as: before))
        #expect(reread.tiers == before.tiers)
        #expect(reread.deadline == later)
    }

    @Test func draftOfferTermsAreNotLocked() async {
        let model = TierEditorViewModel(repositories: draftRepositories(), vendorId: ID.fermeRive, offerId: ID.potatoOffer)
        await model.load()
        #expect(!model.areTermsLocked)
        let create = TierEditorViewModel(repositories: .fake(behavior: .instant), vendorId: ID.fermeRive)
        #expect(!create.areTermsLocked)
    }

    /// Le dépôt fake refuse comme firestore.rules : prix changé sur un lot actif, ou pause sans la marque.
    @Test func fakeRepositoryRefusesChangingAPublishedOffersTerms() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let before = try await repos.offers.offer(id: ID.potatoOffer)
        var pricier = before
        pricier.tiers[0].priceCents += 500
        await #expect(throws: AppError.permissionDenied) { try await repos.offers.saveOffer(pricier) }
        var unmarked = before
        unmarked.status = .draft
        unmarked.wasPublished = false
        await #expect(throws: AppError.permissionDenied) { try await repos.offers.saveOffer(unmarked) }
        var paused = before
        paused.status = .draft
        try await repos.offers.saveOffer(paused)
        var later = paused
        later.deadline = before.deadline.addingTimeInterval(3_600)
        try await repos.offers.saveOffer(later)
        #expect(try await repos.offers.offer(id: ID.potatoOffer).areTermsLocked)
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

    @Test func requiresAShareWeight() {
        let model = validEditor()
        model.share.weight.value = 0
        expectInvalid(model, "Indique ce que contient une part : un poids plus grand que 0 (par exemple « sac de 10 kg »).")
    }

    @Test func savesTheStructuredShare() throws {
        let model = validEditor()
        model.share = ShareSpec(container: .crate, count: 2, weight: .init(2.5, .kilogram), valueCents: 1_299)
        let offer = try model.validatedOffer()
        #expect(offer.share == model.share)
        #expect(offer.shareUnit == "2 caisses de 2,5 kg")
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

    // MARK: Plafonds de firestore.rules

    @Test func totalSharesIsCappedAtTenThousand() {
        let model = validEditor()
        model.totalShares = 10_000
        #expect(model.validationError == nil)
        model.totalShares = 10_001
        expectInvalid(model, "Le lot ne peut pas dépasser 10 000 parts.")
    }

    @Test func tiersAreCappedAtTen() {
        let model = validEditor()
        model.tiers = (1...10).map { Draft(minShares: $0, priceCents: 2_000 - $0 * 100) }
        #expect(model.validationError == nil)
        model.tiers = (1...11).map { Draft(minShares: $0, priceCents: 2_000 - $0 * 100) }
        expectInvalid(model, "Un lot ne peut pas avoir plus de 10 paliers de prix.")
    }

    @Test func addTierStopsAtTen() {
        let model = validEditor()
        for _ in 0..<20 { model.addTier() }
        #expect(model.tiers.count == OfferLifecycle.maxTiers)
    }
}
