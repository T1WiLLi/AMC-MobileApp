// VendorOnboardingViewModel.swift
// T-158 : n'importe quel compte peut ouvrir le portail Vendeurs. Sans vendeur rattaché, il décrit sa production :
// type et nom → production → catégories et quartiers → photos (facultatif) → premier produit (facultatif) → fini.
// À la fin : `vendors/vendor-{uid}` (non vérifié, ownerId = uid), puis `users/{uid}.vendorId`
// (`AppContextResolver.createVendor`), puis le premier produit s'il y en a un. Le portail s'ouvre aussitôt ;
// l'équipe LeGrenier vérifie le profil en parallèle (badge « En vérification »), rien n'est bloqué.

import Foundation
import Observation

@MainActor
@Observable
final class VendorOnboardingViewModel {
    /// Étapes, dans l'ordre.
    enum Step: Int, CaseIterable, Comparable, Sendable {
        case identity
        case production
        case reach
        case photos
        case product
        case done

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }

        /// Étapes à remplir (la dernière est un récapitulatif).
        static let formSteps: [Step] = [.identity, .production, .reach, .photos, .product]

        var title: String {
            switch self {
            case .identity: String(localized: "Qui vend ?")
            case .production: String(localized: "Ta production")
            case .reach: String(localized: "Quoi et où ?")
            case .photos: String(localized: "Montre ta production")
            case .product: String(localized: "Ton premier produit")
            case .done: String(localized: "Ton espace vendeur est prêt !")
            }
        }

        var subtitle: String {
            switch self {
            case .identity: String(localized: "Les familles verront ce nom sur tes lots et sur ta page.")
            case .production: String(localized: "Raconte ce que tu cultives ou fabriques, et comment. C'est ce qui donne confiance aux familles.")
            case .reach: String(localized: "On montre tes lots aux groupes des quartiers que tu dessers.")
            case .photos: String(localized: "Facultatif. Une belle photo de ta ferme ou de tes produits attire l'œil.")
            case .product: String(localized: "Facultatif. Ajoute-le maintenant pour publier un lot tout de suite, ou plus tard depuis l'onglet Produits.")
            case .done: String(localized: "Tu peux déjà publier des lots. L'équipe LeGrenier vérifie ton profil en parallèle.")
            }
        }

        var systemImage: String {
            switch self {
            case .identity: "storefront.fill"
            case .production: "leaf.fill"
            case .reach: "map.fill"
            case .photos: "photo.on.rectangle.angled"
            case .product: "shippingbox.fill"
            case .done: "checkmark.seal.fill"
            }
        }
    }

    // MARK: Règles (pures, alignées sur firestore.rules `isValidNewVendor`)

    nonisolated enum Rules {
        static let nameLength = 2...120
        static let descriptionMinLength = 20
        static let descriptionMaxLength = 2_000
        static let maxZones = 20
        static let maxPhotos = 10

        static func identityError(kind: Vendor.Kind?, legalName: String) -> String? {
            guard kind != nil else { return String(localized: "Choisis ce qui te décrit le mieux.") }
            let name = trimmed(legalName)
            if name.isEmpty { return String(localized: "Indique le nom de ta ferme ou de ton commerce.") }
            if name.count < nameLength.lowerBound { return String(localized: "Le nom doit faire au moins 2 caractères.") }
            if name.count > nameLength.upperBound { return String(localized: "Le nom doit faire 120 caractères ou moins.") }
            return nil
        }

        static func productionError(_ description: String) -> String? {
            let text = trimmed(description)
            if text.count < descriptionMinLength {
                return String(localized: "Encore \(descriptionMinLength - text.count) caractères : une ou deux phrases suffisent.")
            }
            if text.count > descriptionMaxLength {
                return String(localized: "La description doit faire 2 000 caractères ou moins.")
            }
            return nil
        }

        static func reachError(categories: Set<Product.Category>, zones: [String]) -> String? {
            if categories.isEmpty { return String(localized: "Choisis au moins une catégorie de produits.") }
            if zones.isEmpty { return String(localized: "Choisis au moins un quartier desservi.") }
            if zones.count > maxZones { return String(localized: "Tu peux desservir 20 quartiers au plus.") }
            return nil
        }

        static func trimmed(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: Champs

    var kind: Vendor.Kind?
    var legalName = ""
    var productionDescription = ""
    private(set) var categories: Set<Product.Category> = []
    /// Quartiers choisis, dans l'ordre du choix.
    private(set) var neighborhoods: [MontrealNeighborhood] = []
    var neighborhoodQuery = ""
    /// Photos choisies (URL locales d'aperçu), dans l'ordre : la première est la couverture.
    private(set) var photoURLs: [URL] = []
    /// Données JPEG des photos choisies, par URL locale.
    private var pendingPhotos: [URL: Data] = [:]
    /// Premier produit (facultatif), validé et enregistré par l'éditeur de produit du catalogue.
    let product: ProductEditorViewModel

    // MARK: État

    private(set) var step: Step = .identity
    private(set) var isSaving = false
    private(set) var isAddingPhoto = false
    private(set) var saveError: AppError?
    private(set) var photoError: AppError?
    /// Vendeur créé à la fin ; nil avant.
    private(set) var createdVendor: Vendor?
    /// Premier produit enregistré ; nil s'il n'y en a pas (ou s'il n'a pas pu l'être).
    private(set) var savedProduct: Product?
    /// Le vendeur est créé mais le premier produit a échoué : on le dit, sans bloquer.
    private(set) var productSaveFailed = false
    /// Le vendeur est créé mais ses photos n'ont pas pu être envoyées : on le dit, sans bloquer.
    private(set) var photosSaveFailed = false

    let userId: String
    /// Id du vendeur créé (connu d'avance : un vendeur par compte).
    let vendorId: String
    private let repositories: AppRepositories
    /// Stockage final des photos (documents `media` Firestore en live) : utilisable seulement une fois
    /// le vendeur créé et rattaché au compte (firestore.rules : `isVendorOf`).
    private let photoStore: any VendorPhotoStoring
    /// Copie locale des photos choisies avant la création du vendeur (aperçu à l'écran).
    private let stagingStore: any VendorPhotoStoring

    init(
        repositories: AppRepositories,
        userId: String,
        photoStore: (any VendorPhotoStoring)? = nil,
        stagingStore: any VendorPhotoStoring = LocalVendorPhotoStore()
    ) {
        self.repositories = repositories
        self.userId = userId
        self.vendorId = Vendor.ownedId(forUserId: userId)
        self.photoStore = photoStore ?? ImageStoreVendorPhotoStore(images: repositories.images)
        self.stagingStore = stagingStore
        self.product = ProductEditorViewModel(
            repositories: repositories,
            vendorId: Vendor.ownedId(forUserId: userId),
            photoUploader: ImageStoreProductPhotoUploader(images: repositories.images)
        )
    }

    convenience init(context: AppContext) {
        self.init(repositories: context.repositories, userId: context.userId)
    }

    // MARK: Dérivés

    var stepNumber: Int { min(step.rawValue + 1, Step.formSteps.count) }
    var stepCount: Int { Step.formSteps.count }
    var progress: Double { Double(stepNumber) / Double(stepCount) }
    var canGoBack: Bool { step > .identity && step != .done && !isSaving }

    /// Codes de zone enregistrés (`servedZones`), sans doublon.
    var zones: [String] {
        var seen = Set<String>()
        return neighborhoods.map(VendorProfileViewModel.zone(for:)).filter { seen.insert($0).inserted }
    }

    /// Catégories dans l'ordre du catalogue.
    var orderedCategories: [Product.Category] { Product.Category.allCases.filter(categories.contains) }

    /// Quartiers proposés : la recherche (sans casse ni accents), choisis exclus.
    var neighborhoodSuggestions: [MontrealNeighborhood] {
        let query = Rules.trimmed(neighborhoodQuery)
        return MontrealNeighborhood.all
            .filter { !neighborhoods.contains($0) && (query.isEmpty || $0.name.localizedStandardContains(query)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Un champ du premier produit est rempli : il faut alors qu'il soit valide.
    var hasProductDraft: Bool {
        [product.name, product.unit, product.origin, product.referencePriceText].contains { !Rules.trimmed($0).isEmpty }
    }

    /// Ce qui empêche de passer à l'étape suivante, en français ; nil si on peut continuer.
    var stepError: String? {
        switch step {
        case .identity: Rules.identityError(kind: kind, legalName: legalName)
        case .production: Rules.productionError(productionDescription)
        case .reach: Rules.reachError(categories: categories, zones: zones)
        case .photos: nil
        case .product: hasProductDraft ? product.validationError?.localizedDescription : nil
        case .done: nil
        }
    }

    var canContinue: Bool { stepError == nil && !isSaving && !isAddingPhoto }
    var canAddPhoto: Bool { photoURLs.count < Rules.maxPhotos && !isAddingPhoto }

    // MARK: Récapitulatif

    var identitySummary: String {
        let kindTitle = kind.map(VendorKindText.title(for:)) ?? ""
        return "\(Rules.trimmed(legalName)) · \(kindTitle)"
    }

    var categoriesSummary: String {
        orderedCategories.map(\.title).formatted(.list(type: .and).locale(AppLanguage.formattingLocale))
    }

    var zonesSummary: String {
        neighborhoods.map(\.name).formatted(.list(type: .and).locale(AppLanguage.formattingLocale))
    }

    var photosSummary: String {
        if photoURLs.isEmpty { return String(localized: "Aucune pour l'instant") }
        if photosSaveFailed { return String(localized: "Pas envoyées : ajoute-les depuis ton profil") }
        return FrenchPlural.count(photoURLs.count, "photo")
    }

    var productSummary: String {
        if let savedProduct { return savedProduct.name }
        if productSaveFailed { return String(localized: "Pas enregistré : ajoute-le depuis l'onglet Produits") }
        return String(localized: "Plus tard, depuis l'onglet Produits")
    }

    // MARK: Choix

    func isSelected(_ category: Product.Category) -> Bool { categories.contains(category) }

    func toggle(_ category: Product.Category) {
        if categories.contains(category) { categories.remove(category) } else { categories.insert(category) }
    }

    func isSelected(_ neighborhood: MontrealNeighborhood) -> Bool { neighborhoods.contains(neighborhood) }

    func toggle(_ neighborhood: MontrealNeighborhood) {
        if let index = neighborhoods.firstIndex(of: neighborhood) {
            neighborhoods.remove(at: index)
        } else if zones.count < Rules.maxZones {
            neighborhoods.append(neighborhood)
        }
    }

    // MARK: Photos

    /// Garde l'image choisie (PhotosPicker) en local pour l'aperçu ; elle part au stockage final après la
    /// création du vendeur. Renvoie true si elle a été ajoutée.
    @discardableResult
    func addPhoto(data: Data) async -> Bool {
        photoError = nil
        guard photoURLs.count < Rules.maxPhotos else {
            photoError = .invalidInput(String(localized: "Tu peux ajouter 10 photos au plus."))
            return false
        }
        guard !data.isEmpty else {
            photoError = .invalidInput(String(localized: "Cette image est vide."))
            return false
        }
        isAddingPhoto = true
        defer { isAddingPhoto = false }
        do {
            // Image réduite comme les photos de produit ; le stockage final la recadre en 4:3.
            let jpeg = ProductPhoto.jpegData(from: data) ?? data
            let localURL = try await stagingStore.store(jpeg, vendorId: vendorId)
            pendingPhotos[localURL] = jpeg
            photoURLs.append(localURL)
            return true
        } catch {
            photoError = AppError(error)
            return false
        }
    }

    func removePhoto(_ url: URL) {
        photoURLs.removeAll { $0 == url }
        pendingPhotos[url] = nil
    }

    // MARK: Navigation

    /// Étape suivante ; à l'étape du produit, crée le vendeur (et le produit) puis montre le récapitulatif.
    func next() async {
        guard canContinue else { return }
        switch step {
        case .product:
            await save()
        case .done:
            return
        default:
            step = Step(rawValue: step.rawValue + 1) ?? .done
        }
    }

    func back() {
        guard canGoBack, let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    // MARK: Enregistrement

    /// Vendeur d'abord, puis rattachement au profil, puis le premier produit (qui exige le rattachement).
    /// Un nouvel essai après un échec réutilise le vendeur déjà créé.
    func save() async {
        guard !isSaving, Rules.identityError(kind: kind, legalName: legalName) == nil,
              Rules.productionError(productionDescription) == nil,
              Rules.reachError(categories: categories, zones: zones) == nil,
              let kind
        else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        let draft = Vendor(
            id: vendorId,
            legalName: Rules.trimmed(legalName),
            kind: kind,
            description: Rules.trimmed(productionDescription),
            // Les photos suivent, une fois le vendeur rattaché au compte (les règles l'exigent).
            photoURLs: [],
            servedZones: zones,
            averageRating: nil,
            isVerified: false,
            ownerId: userId,
            productCategories: orderedCategories
        )
        do {
            createdVendor = try await AppContextResolver(repositories: repositories)
                .createVendor(draft, forUserId: userId)
        } catch {
            saveError = AppError(error)
            return
        }
        if let vendor = createdVendor, vendor.photoURLs.isEmpty, !photoURLs.isEmpty {
            await uploadPhotos(to: vendor)
        }
        if hasProductDraft, savedProduct == nil {
            savedProduct = await product.save()
            productSaveFailed = savedProduct == nil
        }
        step = .done
    }

    /// Envoie les photos choisies au stockage final et les pose sur le vendeur. Un échec ne bloque pas :
    /// le producteur pourra les ajouter depuis son profil.
    private func uploadPhotos(to vendor: Vendor) async {
        do {
            var urls: [URL] = []
            for localURL in photoURLs {
                guard let data = pendingPhotos[localURL] else { continue }
                urls.append(try await photoStore.store(data, vendorId: vendor.id))
            }
            var updated = vendor
            updated.photoURLs = urls
            try await repositories.vendors.saveVendor(updated)
            createdVendor = updated
            photosSaveFailed = false
        } catch {
            photosSaveFailed = true
        }
    }
}
