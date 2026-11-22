import Foundation
import Testing
@testable import AMC_MobileApp

/// Éditeur de produit du catalogue vendeur (T-064, RQ-032).
@MainActor
struct ProductEditorViewModelTests {
    private typealias ID = FakeData.ID

    private func validEditor(_ repos: AppRepositories = .fake(behavior: .instant)) -> ProductEditorViewModel {
        let model = ProductEditorViewModel(repositories: repos, vendorId: ID.fermeRive)
        model.name = "  Carottes nantaises "
        model.category = .produce
        model.unit = "sac de 5 kg"
        model.origin = "Mirabel, QC"
        model.referencePriceText = "3,49"
        return model
    }

    private func expectInvalid(_ model: ProductEditorViewModel, _ message: String) {
        #expect(model.validationError == .invalidInput(message))
        #expect(!model.canSave)
    }

    // MARK: Prix

    @Test(arguments: [
        ("3,49", 349), ("3.49", 349), ("12", 1_200), ("12,5", 1_250), (" 3,49 $ ", 349),
        ("1 234,50", 123_450), ("1\u{00A0}234,50 $", 123_450), (",99", 99), ("0,05", 5),
    ])
    func parsesFrenchPrices(text: String, cents: Int) {
        #expect(ProductEditorViewModel.parseCents(text) == cents)
    }

    @Test(arguments: ["", "abc", "-3,49", "3,499", "3,4,9", "3$49", ",", "1e3"])
    func rejectsInvalidPrices(text: String) {
        #expect(ProductEditorViewModel.parseCents(text) == nil)
    }

    @Test func formatsPriceText() {
        #expect(ProductEditorViewModel.priceText(349) == "3,49")
        #expect(ProductEditorViewModel.priceText(1_205) == "12,05")
        #expect(ProductEditorViewModel.priceText(1_200) == "12,00")
    }

    // MARK: Validation

    @Test func validEditorCanSave() {
        let model = validEditor()
        #expect(model.validationError == nil)
        #expect(model.canSave)
        #expect(model.referenceGroceryPriceCents == 349)
        #expect(model.categories.count == 9)
        #expect(model.categories.map(\.title).contains("Produits ménagers"))
    }

    @Test func validationRules() {
        let model = validEditor()
        model.name = "   "
        expectInvalid(model, "Donne un nom au produit.")
        model.name = String(repeating: "a", count: 81)
        expectInvalid(model, "Le nom du produit doit faire 80 caractères ou moins.")
        model.name = "Carottes"
        model.unit = " "
        expectInvalid(model, "Choisis l'unité de vente (kg, unité, douzaine…).")
        model.unit = "kg"
        model.origin = ""
        expectInvalid(model, "Indique la provenance du produit (par exemple « Mirabel, QC »).")
        model.origin = "Laval, QC"
        model.referencePriceText = ""
        expectInvalid(model, "Indique le prix en épicerie, pour calculer l'économie des familles.")
        model.referencePriceText = "trois"
        expectInvalid(model, "Le prix en épicerie doit être un montant comme « 3,49 ».")
        model.referencePriceText = "0,00"
        expectInvalid(model, "Le prix en épicerie doit être supérieur à 0 $.")
        model.referencePriceText = "2,99"
        #expect(model.canSave)
    }

    // MARK: Étiquettes

    @Test func tagsAreDedupedAndOrdered() {
        let model = validEditor()
        model.addTag(.local)
        model.addTag(.organic)
        model.addTag(.local)
        #expect(model.tags == [.organic, .local])
        model.toggleTag(.vegan)
        #expect(model.isTagged(.vegan))
        model.toggleTag(.vegan)
        #expect(!model.isTagged(.vegan))
        model.removeTag(.organic)
        #expect(model.tags == [.local])
        model.setTags([.halal, .local, .halal])
        #expect(model.tags == [.halal, .local])
    }

    // MARK: Création et modification

    @Test func savesANewProduct() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let model = validEditor(repos)
        model.addTag(.organic)
        await model.load()
        #expect(model.loadState.error == nil)
        #expect(!model.isEditing)

        let saved = try #require(await model.save())
        #expect(saved.id.hasPrefix("product-"))
        #expect(saved.name == "Carottes nantaises")
        #expect(saved.vendorId == ID.fermeRive)
        #expect(saved.referenceGroceryPriceCents == 349)
        #expect(saved.tags == [.organic])
        #expect(saved.photoURL == nil)
        #expect(model.saveState.value == saved)
        #expect(model.mode == .edit(productId: saved.id))

        let stored = try await repos.vendors.product(id: saved.id)
        #expect(stored == saved)
        let catalog = try await repos.vendors.products(ofVendor: ID.fermeRive)
        #expect(catalog.count == 3)

        // Un deuxième enregistrement modifie le même produit.
        model.referencePriceText = "3,99"
        let again = try #require(await model.save())
        #expect(again.id == saved.id)
        #expect(try await repos.vendors.products(ofVendor: ID.fermeRive).count == 3)
    }

    @Test func editsAnExistingProduct() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let model = ProductEditorViewModel(repositories: repos, vendorId: ID.fermeRive, productId: ID.potatoes)
        await model.load()
        #expect(model.loadState.error == nil)
        #expect(model.isEditing)
        #expect(model.name == "Pommes de terre jaunes")
        #expect(model.category == .produce)
        #expect(model.unit == "sac de 10 kg")
        #expect(model.origin == "Mirabel, QC")
        #expect(model.tags == [.organic, .local])
        #expect(model.referencePriceText == "15,99")
        #expect(model.canSave)

        model.referencePriceText = "14,49"
        model.removeTag(.organic)
        let saved = try #require(await model.save())
        #expect(saved.id == ID.potatoes)
        let stored = try await repos.vendors.product(id: ID.potatoes)
        #expect(stored.referenceGroceryPriceCents == 1_449)
        #expect(stored.tags == [.local])
    }

    @Test func editingAnotherVendorsProductIsDenied() async {
        let model = ProductEditorViewModel(repositories: .fake(behavior: .instant), vendorId: ID.fermeRive, productId: ID.rice)
        await model.load()
        #expect(model.loadState.error == .permissionDenied)
    }

    @Test func invalidSaveDoesNotCallTheRepository() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let model = validEditor(repos)
        model.name = ""
        #expect(await model.save() == nil)
        #expect(model.saveState.error == .invalidInput("Donne un nom au produit."))
        #expect(try await repos.vendors.products(ofVendor: ID.fermeRive).count == 2)
    }

    @Test func failingRepositoryFails() async {
        let repos = AppRepositories.fake(behavior: .failing(.offline))
        let editing = ProductEditorViewModel(repositories: repos, vendorId: ID.fermeRive, productId: ID.potatoes)
        await editing.load()
        #expect(editing.loadState.error == .offline)

        let creating = validEditor(repos)
        #expect(await creating.save() == nil)
        #expect(creating.saveState.error == .offline)
        #expect(!creating.isEditing)
    }
}
