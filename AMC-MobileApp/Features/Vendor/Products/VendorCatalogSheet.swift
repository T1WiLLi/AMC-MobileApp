// VendorCatalogSheet.swift
// Feuille « Mon catalogue » du portail Vendeur (T-089, S-04) : les produits du vendeur, « Nouveau produit »,
// tap sur un produit pour le modifier ou le retirer. Un produit enregistré apparaît tout de suite dans la liste.
// Ouverte par le bouton `plus.circle` de l'onglet Lots (`.newProductToolbar`), directement sur « Nouveau produit ».

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

    /// Photos dans Storage seulement si les produits sont eux-mêmes dans Firebase ; sinon en mémoire.
    static func uploader(for repositories: AppRepositories) -> any ProductPhotoUploader {
        repositories.vendors is FakeVendorRepository
            ? FakeProductPhotoUploader(behavior: .realistic)
            : ProductPhoto.uploader(mode: FirebaseSetup.mode)
    }

    var body: some View {
        NavigationStack(path: $path) {
            StateView(
                state: model.state,
                empty: .init(
                    title: "Ton catalogue est vide",
                    systemImage: "basket.fill",
                    message: "Ajoute ton premier produit avec sa photo : tu pourras ensuite en faire un lot."
                ),
                retry: { await model.load() }
            ) { products in
                productList(products)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .grenierBackground()
            .navigationTitle("Mon catalogue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { newProductButton }
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
        count > 1 ? "\(count) produits" : "\(count) produit"
    }

    private var newProductButton: some View {
        Button {
            path.append(.create)
        } label: {
            Label("Nouveau produit", systemImage: "plus")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.glassProminent)
        .tint(.grenier)
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityHint("Ouvre le formulaire d'un nouveau produit.")
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
                Text("\(product.unit) · \(product.origin)")
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
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                        .frame(width: side, height: side)
                        .clipShape(.rect(cornerRadius: 14))
                        .accessibilityHidden(true)
                } else {
                    ProductIcon(category: product.category)
                }
            }
        } else {
            ProductIcon(category: product.category)
        }
    }
}

// MARK: - Bouton d'entrée (onglet Lots)

/// Bouton `plus.circle` dans la barre, qui ouvre « Mon catalogue » directement sur « Nouveau produit ».
private struct NewProductToolbarModifier: ViewModifier {
    let repositories: AppRepositories
    let vendorId: String
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Nouveau produit", systemImage: "plus.circle") {
                        isPresented = true
                    }
                    .accessibilityHint("Ajoute un produit à ton catalogue, avec sa photo.")
                }
            }
            .sheet(isPresented: $isPresented) {
                VendorCatalogSheet(repositories: repositories, vendorId: vendorId, startsWithNewProduct: true)
            }
    }
}

extension View {
    /// Ajoute le bouton « Nouveau produit » (T-089) à la barre de l'écran.
    func newProductToolbar(repositories: AppRepositories, vendorId: String) -> some View {
        modifier(NewProductToolbarModifier(repositories: repositories, vendorId: vendorId))
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
