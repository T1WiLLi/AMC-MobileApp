// ProductEditorViewModel.swift
// Éditeur de produit du catalogue vendeur (T-064, RQ-032) : créer ou modifier un produit.
//
// Usage dans une vue :
//   @State private var model = ProductEditorViewModel(repositories: repos, vendorId: id)                     // nouveau produit
//   @State private var model = ProductEditorViewModel(repositories: repos, vendorId: id, productId: p.id)   // modification
//   .task { await model.load() }
//   Champs liés par `$model.name`, `$model.category`, `$model.unit`, `$model.origin`, `$model.referencePriceText` (« 3,49 »).
//   Étiquettes : `model.toggleTag(.organic)` / `model.isTagged(.organic)`.
//   `model.validationError` pour l'erreur en direct ; bouton actif si `model.canSave` ; `await model.save()`.
//
// Pas de téléversement de photo : `photoURL` est conservé tel quel (nil pour un nouveau produit).

import Foundation
import Observation

@Observable @MainActor
final class ProductEditorViewModel {
    /// Mode de l'éditeur.
    nonisolated enum Mode: Sendable, Hashable {
        case create
        case edit(productId: String)
    }

    // MARK: Champs éditables

    var name: String = ""
    var category: Product.Category = .produce
    /// Unité de vente : « kg », « sac de 10 kg », « douzaine »…
    var unit: String = ""
    var origin: String = ""
    /// Étiquettes alimentaires, sans doublon, dans l'ordre de `DietaryTag.allCases`.
    private(set) var tags: [DietaryTag] = []
    /// Prix d'épicerie de référence saisi en français : « 3,49 », « 3,49 $ », « 12 ».
    var referencePriceText: String = ""

    // MARK: État

    private(set) var mode: Mode
    /// Chargement du produit en mode modification (`.loaded` d'emblée en création).
    private(set) var loadState: LoadState<Void> = .idle
    /// Résultat de la dernière sauvegarde : `.loaded(product)` si enregistré, `.failed(…)` sinon.
    private(set) var saveState: LoadState<Product> = .idle
    /// Photo actuelle (placeholder si nil) ; conservée telle quelle à l'enregistrement.
    private(set) var photoURL: URL?

    let vendorId: String

    private let repositories: AppRepositories

    init(repositories: AppRepositories, vendorId: String, productId: String? = nil) {
        self.repositories = repositories
        self.vendorId = vendorId
        self.mode = productId.map { .edit(productId: $0) } ?? .create
    }

    // MARK: Dérivés

    /// Catégories de RQ-039, pour le sélecteur (libellés via `title`).
    var categories: [Product.Category] { Product.Category.allCases }
    var isEditing: Bool { if case .edit = mode { true } else { false } }
    var isSaving: Bool { saveState.isLoading }

    /// Prix de référence en cents, nil si la saisie n'est pas un montant valide.
    var referenceGroceryPriceCents: Cents? { Self.parseCents(referencePriceText) }

    /// Première règle non respectée, en français ; nil si le produit est enregistrable.
    var validationError: AppError? {
        do {
            _ = try validatedProduct()
            return nil
        } catch {
            return error
        }
    }

    var canSave: Bool { validationError == nil && !isSaving && !loadState.isLoading }

    // MARK: Étiquettes

    func isTagged(_ tag: DietaryTag) -> Bool { tags.contains(tag) }

    /// Ajoute l'étiquette (sans effet si elle y est déjà).
    func addTag(_ tag: DietaryTag) {
        guard !tags.contains(tag) else { return }
        tags = Self.normalized(tags + [tag])
    }

    func removeTag(_ tag: DietaryTag) {
        tags.removeAll { $0 == tag }
    }

    func toggleTag(_ tag: DietaryTag) {
        isTagged(tag) ? removeTag(tag) : addTag(tag)
    }

    /// Remplace toutes les étiquettes (doublons retirés).
    func setTags(_ newTags: [DietaryTag]) {
        tags = Self.normalized(newTags)
    }

    // MARK: Actions

    /// Charge le produit à modifier. Lève `.permissionDenied` (dans `loadState`) s'il appartient à un autre vendeur.
    func load() async {
        guard case .edit(let productId) = mode else {
            loadState = .loaded(())
            return
        }
        loadState = .loading
        do {
            let product = try await repositories.vendors.product(id: productId)
            guard product.vendorId == vendorId else { throw AppError.permissionDenied }
            apply(product)
            loadState = .loaded(())
        } catch {
            loadState = .failed(AppError(error))
        }
    }

    /// Valide puis enregistre via `vendors.saveProduct`. Renvoie le produit, nil en cas d'échec (voir `saveState`).
    /// Après une création réussie, l'éditeur passe en mode modification de ce produit.
    @discardableResult
    func save() async -> Product? {
        let product: Product
        do {
            product = try validatedProduct()
        } catch {
            saveState = .failed(error)
            return nil
        }
        saveState = .loading
        do {
            try await repositories.vendors.saveProduct(product)
            mode = .edit(productId: product.id)
            saveState = .loaded(product)
            return product
        } catch {
            saveState = .failed(AppError(error))
            return nil
        }
    }

    /// Construit le produit à enregistrer, ou lève `AppError.invalidInput` avec la première règle non respectée.
    func validatedProduct() throws(AppError) -> Product {
        let name = Self.trimmed(name)
        let unit = Self.trimmed(unit)
        let origin = Self.trimmed(origin)
        guard !name.isEmpty else { throw .invalidInput("Donne un nom au produit.") }
        guard name.count <= 80 else { throw .invalidInput("Le nom du produit doit faire 80 caractères ou moins.") }
        guard !unit.isEmpty else {
            throw .invalidInput("Indique l'unité de vente (par exemple « sac de 10 kg » ou « douzaine »).")
        }
        guard !origin.isEmpty else { throw .invalidInput("Indique la provenance du produit (par exemple « Mirabel, QC »).") }
        guard !Self.trimmed(referencePriceText).isEmpty else {
            throw .invalidInput("Indique le prix en épicerie, pour calculer l'économie des familles.")
        }
        guard let cents = referenceGroceryPriceCents else {
            throw .invalidInput("Le prix en épicerie doit être un montant comme « 3,49 ».")
        }
        guard cents > 0 else { throw .invalidInput("Le prix en épicerie doit être supérieur à 0 $.") }

        let productId: String = switch mode {
        case .create: "product-\(UUID().uuidString.lowercased())"
        case .edit(let id): id
        }
        return Product(
            id: productId,
            vendorId: vendorId,
            name: name,
            category: category,
            unit: unit,
            origin: origin,
            tags: tags,
            photoURL: photoURL,
            referenceGroceryPriceCents: cents
        )
    }

    // MARK: Utilitaires

    /// Convertit une saisie française en cents : « 3,49 » → 349, « 3.49 » → 349, « 12 » → 1200, « 1 234,50 $ » → 123450.
    /// nil si vide, négatif, plus de deux décimales ou caractères inattendus.
    nonisolated static func parseCents(_ text: String) -> Cents? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasSuffix("$") { cleaned.removeLast() }
        // Espaces (y compris insécables) utilisés comme séparateurs de milliers.
        cleaned = cleaned.filter { !$0.isWhitespace }
        cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let whole = parts[0]
        let fraction = parts.count == 2 ? parts[1] : ""
        guard !(whole.isEmpty && fraction.isEmpty),
              whole.allSatisfy(\.isASCIIDigit), fraction.allSatisfy(\.isASCIIDigit),
              fraction.count <= 2, whole.count <= 7 else { return nil }
        let dollars = Int(whole) ?? 0
        let cents = fraction.isEmpty ? 0 : (Int(fraction) ?? 0) * (fraction.count == 1 ? 10 : 1)
        return dollars * 100 + cents
    }

    /// Cents → saisie française : 349 → « 3,49 ».
    nonisolated static func priceText(_ cents: Cents) -> String {
        let remainder = cents % 100
        return "\(cents / 100)," + (remainder < 10 ? "0\(remainder)" : "\(remainder)")
    }

    private nonisolated static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Retire les doublons et range dans l'ordre de `DietaryTag.allCases`.
    private nonisolated static func normalized(_ tags: [DietaryTag]) -> [DietaryTag] {
        let set = Set(tags)
        return DietaryTag.allCases.filter { set.contains($0) }
    }

    private func apply(_ product: Product) {
        name = product.name
        category = product.category
        unit = product.unit
        origin = product.origin
        tags = Self.normalized(product.tags)
        photoURL = product.photoURL
        referencePriceText = Self.priceText(product.referenceGroceryPriceCents)
    }
}

private extension Character {
    nonisolated var isASCIIDigit: Bool { isASCII && isNumber }
}
