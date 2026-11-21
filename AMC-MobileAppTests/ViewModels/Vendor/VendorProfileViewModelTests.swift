import Foundation
import Testing
@testable import AMC_MobileApp

/// Profil vendeur (T-076, RQ-016).
@MainActor
struct VendorProfileViewModelTests {
    private typealias ID = FakeData.ID

    /// Photo enregistrée en mémoire : renvoie une URL prévisible, ou lève l'erreur donnée.
    private struct StubPhotoStore: VendorPhotoStoring {
        var failure: AppError?
        func store(_ data: Data, vendorId: String) async throws -> URL {
            if let failure { throw failure }
            return URL(string: "https://example.com/\(vendorId)/\(data.count).jpg")!
        }
    }

    private func makeModel(
        repositories: AppRepositories = .fake(behavior: .instant),
        photoStore: StubPhotoStore = StubPhotoStore()
    ) -> VendorProfileViewModel {
        VendorProfileViewModel(repositories: repositories, vendorId: ID.fermeRive, photoStore: photoStore)
    }

    @Test func loadsVendorAndNamesZonesFromGroups() async throws {
        let model = makeModel()
        #expect(model.state.value == nil)
        await model.load()

        let vendor = try #require(model.vendor)
        #expect(vendor.legalName == "Ferme Bio-Rive")
        #expect(model.description == vendor.description)
        #expect(model.servedZones == ["f25d", "f25e"])
        #expect(model.label(forZone: "f25d") == "Saint-Michel")
        #expect(model.label(forZone: "f25e") == "Hochelaga")
        #expect(model.label(forZone: "zzzz") == "zzzz")
        #expect(model.zoneSuggestions.isEmpty)
        #expect(!model.hasChanges)
        #expect(!model.canSave)
    }

    @Test func loadFailureBecomesFailedState() async {
        let model = makeModel(repositories: .fake(behavior: .failing(.offline)))
        await model.load()
        #expect(model.state.error == .offline)
    }

    @Test func unknownVendorIsNotFound() async {
        let model = VendorProfileViewModel(repositories: .fake(behavior: .instant), vendorId: "inconnu")
        await model.load()
        #expect(model.state.error == .notFound)
    }

    @Test func savesEditableFieldsAndPersistsThem() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        let model = makeModel(repositories: repositories)
        await model.load()

        model.description = "  Légumes bio de Mirabel, cueillis la veille de la livraison.  "
        model.removeZone("f25e")
        #expect(model.zoneSuggestions.map(\.id) == ["f25e"])
        #expect(await model.addPhoto(data: Data([1, 2, 3])) == nil)
        #expect(model.hasChanges)
        #expect(model.canSave)

        let saved = try #require(await model.save())
        #expect(saved.description == "Légumes bio de Mirabel, cueillis la veille de la livraison.")
        #expect(saved.servedZones == ["f25d"])
        #expect(saved.photoURLs == [URL(string: "https://example.com/\(ID.fermeRive)/3.jpg")!])
        #expect(model.saveState.value == saved)
        #expect(!model.hasChanges)

        let stored = try await repositories.vendors.vendor(id: ID.fermeRive)
        #expect(stored == saved)
        #expect(stored.legalName == "Ferme Bio-Rive")
    }

    @Test func rejectsShortDescriptionWithoutSaving() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        let model = makeModel(repositories: repositories)
        await model.load()

        model.description = "Trop court"
        guard case .invalidInput = model.validationError else {
            Issue.record("validationError attendu : \(String(describing: model.validationError))")
            return
        }
        #expect(!model.canSave)
        #expect(await model.save() == nil)
        guard case .invalidInput = model.saveState.error else {
            Issue.record("saveState attendu en .invalidInput")
            return
        }
        #expect(try await repositories.vendors.vendor(id: ID.fermeRive).description != "Trop court")
    }

    @Test func requiresAtLeastOneZone() async {
        let model = makeModel()
        await model.load()
        model.removeZone("f25d")
        model.removeZone("f25e")
        #expect(model.validationError == .invalidInput("Choisis au moins une zone desservie : c'est là que tes lots apparaîtront."))
    }

    @Test func addZoneNormalizesAndRejectsDuplicatesAndBlanks() async {
        let model = makeModel()
        await model.load()

        #expect(model.addZone("  F25F ") == nil)
        #expect(model.servedZones == ["f25d", "f25e", "f25f"])
        #expect(model.addZone("f25d") == .invalidInput("Tu dessers déjà cette zone."))
        #expect(model.addZone("   ") == .invalidInput("Saisis un code de zone."))
        #expect(model.servedZones.count == 3)
    }

    @Test func capsZonesAtTwenty() async {
        let model = makeModel()
        await model.load()
        model.servedZones = (0..<VendorProfileViewModel.maxZones).map { "z\($0)" }
        #expect(model.addZone("encore") == .invalidInput("Tu peux desservir 20 zones au plus."))
    }

    @Test func photosCanBeReorderedRemovedAndAreCapped() async {
        let model = makeModel()
        await model.load()

        for size in 1...VendorProfileViewModel.maxPhotos {
            #expect(await model.addPhoto(data: Data(count: size)) == nil)
        }
        #expect(!model.canAddPhoto)
        #expect(await model.addPhoto(data: Data([9])) == .invalidInput("Tu peux ajouter 10 photos au plus."))

        let third = model.photoURLs[2]
        model.makeCover(third)
        #expect(model.photoURLs.first == third)
        model.removePhoto(third)
        #expect(model.photoURLs.count == 9)
        #expect(!model.photoURLs.contains(third))
    }

    @Test func photoStoreFailureIsReported() async {
        let model = makeModel(photoStore: StubPhotoStore(failure: .offline))
        await model.load()
        #expect(await model.addPhoto(data: Data([1])) == .offline)
        #expect(model.photoURLs.isEmpty)
        #expect(await model.addPhoto(data: Data()) == .invalidInput("Cette image est vide."))
    }

    @Test func saveWithoutLoadedProfileFails() async {
        let model = VendorProfileViewModel(
            repositories: .fake(behavior: .failing(.offline)), vendorId: ID.fermeRive, photoStore: StubPhotoStore()
        )
        await model.load()
        #expect(model.state.error == .offline)
        model.description = "Une description assez longue pour passer la validation."
        #expect(await model.save() == nil)
        #expect(model.saveState.error == .notFound)
    }

    @Test func discardChangesRestoresSavedValues() async {
        let model = makeModel()
        await model.load()
        model.description = "Autre chose, assez long pour être valide."
        model.removeZone("f25d")
        model.discardChanges()
        #expect(!model.hasChanges)
        #expect(model.servedZones == ["f25d", "f25e"])
    }

    @Test func fakeRepositoryRefusesReadOnlyFields() async throws {
        let repository = FakeVendorRepository(vendors: FakeData.montreal.vendors)
        var vendor = try await repository.vendor(id: ID.fermeRive)
        vendor.legalName = "Autre nom"
        await #expect(throws: AppError.permissionDenied) { try await repository.saveVendor(vendor) }

        vendor = try await repository.vendor(id: ID.fermeRive)
        vendor.id = "inconnu"
        await #expect(throws: AppError.notFound) { try await repository.saveVendor(vendor) }
    }

    @Test func zoneLabelsGroupNeighborhoodsByPrefix() {
        let groups = [
            NeighborhoodGroup(id: "a", name: "A", neighborhood: "Villeray", centerGeohash: "f25dw1", radiusMeters: 500,
                              coordinatorIds: [], householdCount: 3, isPublic: true, inviteCode: "A"),
            NeighborhoodGroup(id: "b", name: "B", neighborhood: "Parc-Extension", centerGeohash: "F25DQ", radiusMeters: 500,
                              coordinatorIds: [], householdCount: 3, isPublic: true, inviteCode: "B"),
            NeighborhoodGroup(id: "c", name: "C", neighborhood: "Court", centerGeohash: "f2", radiusMeters: 500,
                              coordinatorIds: [], householdCount: 3, isPublic: true, inviteCode: "C"),
        ]
        let labels = VendorProfileViewModel.zoneLabels(from: groups)
        #expect(labels.keys.sorted() == ["f25d"])
        #expect(labels["f25d"]?.contains("Parc-Extension") == true)
        #expect(labels["f25d"]?.contains("Villeray") == true)
    }
}
