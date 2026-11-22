// VendorCatalogSheet.swift
// Page « Mes produits » du portail Vendeur (T-089, S-04) : les produits du vendeur, « Nouveau produit »,
// tap sur un produit pour le modifier ou le retirer. Un produit enregistré apparaît tout de suite dans la liste.
// B-052 : page « Mes produits », ouverte par le bouton `basket` de l'onglet Lots (`.myProductsToolbar`),
// « Nouveau produit » en icône de barre (plus de bouton flottant qui cache la liste).

import SwiftUI

struct VendorCatalogSheet: View {
    enum Route: Hashable {
        case create
        case edit(productId: String)
    }

    private let repositories: AppRepositories
    private let vendorId: String
    private let photoUploader: any ProductPhotoUploader
    @State private var model: VendorCatalogViewModel
    @State private var path: [Route]
    @State private var detent: PresentationDetent = .large
    @State private var savedTrigger = 0
    @State private var deletedTrigger = 0
    @Environment(\.dismiss) private var dismiss

    init(
        repositories: AppRepositories,
        vendorId: String,
        photoUploader: (any ProductPhotoUploader)? = nil,
        startsWithNewProduct: Bool = false
    ) {
        self.repositories = repositories
        self.vendorId = vendorId
        self.photoUploader = photoUploader ?? Self.uploader(for: repositories)
        _model = State(initialValue: VendorCatalogViewModel(repositories: repositories, vendorId: vendorId))
        _path = State(initialValue: startsWithNewProduct ? [.create] : [])
    }

    /// Photos dans le dépôt d'images de l'app (documents `media` Firestore en live, mémoire en fake).
    static func uploader(for repositories: AppRepositories) -> any ProductPhotoUploader {
        ImageStoreProductPhotoUploader(images: repositories.images)
    }

    var body: some View {
        NavigationStack(path: $path) {
            StateView(
                state: model.state,
                empty: .init(
                    title: "Aucun produit pour l'instant",
                    systemImage: "basket.fill",
                    message: "Touche + pour ajouter ton premier produit avec sa photo : tu pourras ensuite en faire un lot."
                ),
                retry: { await model.load() }
            ) { products in
                productList(products)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .grenierBackground()
            .navigationTitle("Mes produits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Nouveau produit", systemImage: "plus") { path.append(.create) }
                        .accessibilityHint("Ouvre le formulaire d'un nouveau produit.")
                }
            }
            .navigationDestination(for: Route.self) { route in
                editor(for: route)
            }
            .task {
                if case .idle = model.state { await model.load() }
            }
        }
        .grenierHaptic(.success, trigger: savedTrigger)
        .grenierHaptic(.warning, trigger: deletedTrigger)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.fond)
    }

    // MARK: Liste

    private func productList(_ products: [Product]) -> some View {
        List {
            Section {
                ForEach(products) { product in
                    NavigationLink(value: Route.edit(productId: product.id)) {
                        CatalogProductRow(product: product, isNew: product.id == model.highlightedProductId)
                    }
                    .listRowBackground(Color.surface)
                }
            } header: {
                Label(countText(products.count), systemImage: "basket.fill")
            } footer: {
                Text("Touche un produit pour le modifier, changer sa photo ou le retirer.")
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable { await model.refresh() }
        .grenierAnimation(.smooth, value: products.map(\.id))
    }

    private func countText(_ count: Int) -> String {
        count > 1 ? String(localized: "\(count) produits") : String(localized: "\(count) produit")
    }

    // MARK: Éditeur

    @ViewBuilder
    private func editor(for route: Route) -> some View {
        switch route {
        case .create:
            ProductEditorScreen(
                repositories: repositories, vendorId: vendorId, photoUploader: photoUploader,
                onSaved: productSaved
            )
        case .edit(let productId):
            ProductEditorScreen(
                repositories: repositories, vendorId: vendorId, productId: productId, photoUploader: photoUploader,
                onSaved: productSaved,
                onDeleted: productDeleted
            )
        }
    }

    private func productSaved(_ product: Product) {
        model.productSaved(product)
        savedTrigger += 1
        path.removeAll()
    }

    private func productDeleted(_ productId: String) {
        model.productDeleted(id: productId)
        deletedTrigger += 1
        path.removeAll()
    }
}

// MARK: - Ligne du catalogue

private struct CatalogProductRow: View {
    let product: Product
    let isNew: Bool

    @ScaledMetric(relativeTo: .title2) private var side: CGFloat = 52

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(.headline)
                    .foregroundStyle(.texte)
                Text("\(product.displayUnit) · \(product.origin)")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                Label("\(Money.format(product.referenceGroceryPriceCents)) en épicerie", systemImage: "cart")
                    .font(.caption)
                    .foregroundStyle(.texteSecondaire)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            if isNew {
                Label("À jour", systemImage: "checkmark.seal.fill")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
                    .symbolEffect(.bounce, options: .nonRepeating, value: isNew)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Tout juste enregistré")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = product.photoURL {
            MediaImage(url: url) {
                ProductIcon(category: product.category)
            }
            .frame(width: side, height: side)
            .clipShape(.rect(cornerRadius: 14))
            .accessibilityHidden(true)
        } else {
            ProductIcon(category: product.category)
        }
    }
}

// MARK: - Bouton d'entrée (onglet Lots)

/// Bouton « Mes produits » dans la barre, qui ouvre la page des produits du vendeur (B-052).
private struct MyProductsToolbarModifier: ViewModifier {
    let repositories: AppRepositories
    let vendorId: String
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Mes produits", systemImage: "basket.fill") {
                        isPresented = true
                    }
                    .accessibilityHint("Ajoute, modifie ou retire tes produits, réutilisables pour tes lots.")
                }
            }
            .sheet(isPresented: $isPresented) {
                VendorCatalogSheet(repositories: repositories, vendorId: vendorId)
            }
    }
}

extension View {
    /// Ajoute le bouton « Mes produits » (B-052) à la barre de l'écran.
    func myProductsToolbar(repositories: AppRepositories, vendorId: String) -> some View {
        modifier(MyProductsToolbarModifier(repositories: repositories, vendorId: vendorId))
    }
}

#if DEBUG
#Preview("Catalogue") {
    Color.clear.sheet(isPresented: .constant(true)) {
        VendorCatalogSheet(repositories: .fake(), vendorId: FakeData.ID.fermeRive)
    }
}

#Preview("Catalogue sombre") {
    Color.clear.sheet(isPresented: .constant(true)) {
        VendorCatalogSheet(repositories: .fake(), vendorId: FakeData.ID.fermeRive)
    }
    .preferredColorScheme(.dark)
}

#Preview("Nouveau produit") {
    Color.clear.sheet(isPresented: .constant(true)) {
        VendorCatalogSheet(repositories: .fake(), vendorId: FakeData.ID.fermeRive, startsWithNewProduct: true)
    }
}

#Preview("Catalogue vide") {
    var data = FakeData.montreal
    data.products = []
    return Color.clear.sheet(isPresented: .constant(true)) {
        VendorCatalogSheet(repositories: .fake(data: data), vendorId: FakeData.ID.fermeRive)
    }
}
#endif
