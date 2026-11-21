import Foundation
import Testing
import UIKit
@testable import AMC_MobileApp

/// Nouveau produit avec photo, retrait et catalogue du vendeur (T-089, S-04).
@MainActor
struct ProductCatalogTests {
    private typealias ID = FakeData.ID

    private func validEditor(
        _ repos: AppRepositories = .fake(behavior: .instant),
        uploader: FakeProductPhotoUploader = FakeProductPhotoUploader(),
        productId: String? = nil
    ) -> ProductEditorViewModel {
        let model = ProductEditorViewModel(
            repositories: repos, vendorId: ID.fermeRive, productId: productId, photoUploader: uploader
        )
        model.name = "Farine de sarrasin"
        model.category = .flour
        model.unit = "sac de 2 kg"
        model.origin = "Saint-Jean-de-Matha, QC"
        model.referencePriceText = "8,99"
        return model
    }

    // MARK: Validation

    @Test func validationMessagesAreInFrench() {
        let model = validEditor()
        model.unit = " "
        #expect(model.validationError == .invalidInput(
            "Indique l'unité de vente (par exemple « sac de 10 kg » ou « douzaine »)."
        ))
        model.unit = "kg"
        model.referencePriceText = "0"
        #expect(model.validationError == .invalidInput("Le prix en épicerie doit être supérieur à 0 $."))
        model.referencePriceText = "8,999"
        #expect(model.validationError == .invalidInput("Le prix en épicerie doit être un montant comme « 3,49 »."))
        #expect(!model.canSave)
        model.referencePriceText = "8,99"
        #expect(model.canSave)
    }

    @Test func oversizedPhotoIsRejected() {
        let model = validEditor()
        model.setPhoto(Data(count: ProductPhoto.maxBytes + 1))
        #expect(model.validationError == .invalidInput("La photo doit faire 5 Mo ou moins. Choisis-en une autre."))
        #expect(!model.canSave)
        model.removePhoto()
        #expect(!model.hasPhoto)
        #expect(model.canSave)
    }

    @Test func newProductKeepsTheSameIdAcrossValidations() throws {
        let model = validEditor()
        let first = try model.validatedProduct()
        let second = try model.validatedProduct()
        #expect(first.id == second.id)
        #expect(first.id.hasPrefix("product-"))
    }

    // MARK: Photo

    @Test func savingUploadsThePhotoAndStoresItsURL() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let uploader = FakeProductPhotoUploader()
        let model = validEditor(repos, uploader: uploader)
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
        model.setPhoto(jpeg)
        #expect(model.hasPhoto)

        let saved = try #require(await model.save())
        let path = ProductPhoto.storagePath(vendorId: ID.fermeRive, productId: saved.id)
        #expect(await uploader.photos[path] == jpeg)
        #expect(saved.photoURL?.absoluteString.hasSuffix(path) == true)
        #expect(model.pendingPhotoData == nil)
        #expect(model.photoURL == saved.photoURL)
        #expect(try await repos.vendors.product(id: saved.id).photoURL == saved.photoURL)
    }

    @Test func removingASavedPhotoDeletesItFromStorage() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let uploader = FakeProductPhotoUploader()
        let model = validEditor(repos, uploader: uploader)
        model.setPhoto(Data([1, 2, 3]))
        let saved = try #require(await model.save())

        model.removePhoto()
        let updated = try #require(await model.save())
        #expect(updated.photoURL == nil)
        #expect(await uploader.photos.isEmpty)
        #expect(try await repos.vendors.product(id: saved.id).photoURL == nil)
    }

    @Test func failedUploadDoesNotSaveTheProduct() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let model = validEditor(repos, uploader: FakeProductPhotoUploader(behavior: .failing(.offline)))
        model.setPhoto(Data([1, 2, 3]))
        #expect(await model.save() == nil)
        #expect(model.saveState.error == .offline)
        #expect(model.pendingPhotoData != nil)
        #expect(try await repos.vendors.products(ofVendor: ID.fermeRive).count == 2)
    }

    @Test func jpegIsResizedToTheMaximumDimension() throws {
        let size = CGSize(width: 3200, height: 1600)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let png = try #require(image.pngData())
        let jpeg = try #require(ProductPhoto.jpegData(from: png))
        let resized = try #require(UIImage(data: jpeg))
        #expect(resized.size.width == ProductPhoto.maxDimension)
        #expect(resized.size.height == ProductPhoto.maxDimension / 2)
        #expect(ProductPhoto.jpegData(from: Data("pas une image".utf8)) == nil)
    }

    // MARK: Retrait

    @Test func deletesAProductAndItsPhoto() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let uploader = FakeProductPhotoUploader()
        let creator = validEditor(repos, uploader: uploader)
        creator.setPhoto(Data([1]))
        let saved = try #require(await creator.save())

        #expect(await creator.delete())
        #expect(creator.deleteState.value != nil)
        #expect(await uploader.photos.isEmpty)
        await #expect(throws: AppError.notFound) { try await repos.vendors.product(id: saved.id) }
    }

    @Test func productUsedByAnOpenOfferCannotBeDeleted() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let model = ProductEditorViewModel(repositories: repos, vendorId: ID.fermeRive, productId: ID.potatoes)
        await model.load()
        #expect(await model.delete() == false)
        #expect(model.deleteState.error == .invalidInput(
            "Ce produit est dans un lot ouvert ou en pause : retire d'abord le lot, puis le produit."
        ))
        #expect(try await repos.vendors.product(id: ID.potatoes).name == "Pommes de terre jaunes")
    }

    @Test func newProductCannotBeDeleted() async {
        #expect(await validEditor().delete() == false)
    }

    // MARK: Catalogue

    @Test func savedProductAppearsImmediatelyInTheCatalogue() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let catalog = VendorCatalogViewModel(repositories: repos, vendorId: ID.fermeRive)
        await catalog.load()
        #expect(catalog.products.map(\.name) == ["Pommes Cortland", "Pommes de terre jaunes"])

        let saved = try #require(await validEditor(repos).save())
        catalog.productSaved(saved)
        #expect(catalog.products.map(\.name) == ["Farine de sarrasin", "Pommes Cortland", "Pommes de terre jaunes"])
        #expect(catalog.highlightedProductId == saved.id)

        catalog.productDeleted(id: saved.id)
        #expect(catalog.products.count == 2)
        #expect(catalog.highlightedProductId == nil)
    }

    @Test func otherVendorsProductIsIgnoredByTheCatalogue() async {
        let catalog = VendorCatalogViewModel(repositories: .fake(behavior: .instant), vendorId: ID.fermeRive)
        await catalog.load()
        var product = FakeData.montreal.products[0]
        product.vendorId = ID.moulinsDuNord
        product.id = "product-autre"
        catalog.productSaved(product)
        #expect(!catalog.products.contains { $0.id == "product-autre" })
    }

    @Test func emptyCatalogueAfterLastDeletion() async {
        var data = FakeData.montreal
        data.products = []
        let catalog = VendorCatalogViewModel(repositories: .fake(behavior: .instant, data: data), vendorId: ID.fermeRive)
        await catalog.load()
        #expect(catalog.state == .empty)
    }
}
