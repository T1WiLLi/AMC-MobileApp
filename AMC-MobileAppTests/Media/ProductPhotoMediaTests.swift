import Foundation
import Testing
import UIKit
@testable import AMC_MobileApp

/// Photos de produits dans le dépôt d'images (documents `media` Firestore) : le projet est sur Spark,
/// sans Cloud Storage, et l'ancien envoi Storage échouait en « This item no longer exists ».
@MainActor
struct ProductPhotoMediaTests {
    private let vendorId = FakeData.ID.fermeRive

    private func photo(width: CGFloat = 1_600, height: CGFloat = 1_200) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            for x in stride(from: 0, to: width, by: 20) {
                UIColor(hue: x / width, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                context.fill(CGRect(x: x, y: 0, width: 20, height: height))
            }
        }.jpegData(compressionQuality: 0.9)!
    }

    @Test func productPhotoLivesNextToTheShowcasePhotos() {
        let path = MediaPath.productPhoto(vendorId: "vendor-a", productId: "prod-42")
        #expect(path.documentPath == "vendors/vendor-a/media/photo-product-prod-42")
        #expect(path.spec == .product)
        #expect(MediaPath(documentPath: path.documentPath) == path)
        // Une vitrine garde son propre type.
        #expect(MediaPath(documentPath: "vendors/vendor-a/media/photo-abc") == .vendorPhoto(vendorId: "vendor-a", photoId: "photo-abc"))
    }

    @Test func productPhotoIdMatchesTheFirestoreRule() throws {
        let rule = try Regex("^photo-[A-Za-z0-9-]{1,64}$")
        for productId in ["prod-42", "Ab_c.d/é", String(repeating: "x", count: 200), ""] {
            let id = MediaPath.productPhotoId(productId: productId)
            #expect(id.wholeMatch(of: rule) != nil, "\(id)")
        }
    }

    @Test func uploaderSavesASquareMediaAndDeletesIt() async throws {
        let images = FakeImageStore()
        let uploader = ImageStoreProductPhotoUploader(images: images)
        let url = try await uploader.uploadPhoto(photo(), vendorId: vendorId, productId: "prod-1")
        let path = MediaPath.productPhoto(vendorId: vendorId, productId: "prod-1")
        #expect(MediaURL.source(of: url) == .media(path))
        let saved = try #require(await images.images[path])
        #expect(saved.width == saved.height)
        #expect(saved.jpeg.count <= 300 * 1_024)

        try await uploader.deletePhoto(vendorId: vendorId, productId: "prod-1")
        #expect(await images.images[path] == nil)
    }

    @Test func catalogUsesTheImageStore() {
        #expect(VendorCatalogSheet.uploader(for: .fake(behavior: .instant)) is ImageStoreProductPhotoUploader)
    }
}
