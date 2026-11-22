// VendorSearchScreen.swift
// Onglet Recherche du portail Vendeur (T-129, QA T-094 n° 16) : mon catalogue, mes lots et la demande
// des quartiers. Chaque ligne ouvre l'élément : produit → éditeur de produit, lot → éditeur de paliers,
// quartier ou groupe → fiche de la demande.

import SwiftUI

struct VendorSearchScreen: View {
    /// Élément ouvert en feuille.
    enum Route: Identifiable, Hashable {
        case product(String)
        case offer(String)
        case demand(DemandMapViewModel.DemandPoint)

        var id: String {
            switch self {
            case .product(let id): "product-\(id)"
            case .offer(let id): "offer-\(id)"
            case .demand(let point): "demand-\(point.grouping.rawValue)-\(point.id)"
            }
        }
    }

    private let repositories: AppRepositories
    private let vendorId: String
    @State private var model: VendorSearchViewModel
    @State private var route: Route?
    @State private var openedCount = 0

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(repositories: AppRepositories, vendorId: String) {
        self.repositories = repositories
        self.vendorId = vendorId
        _model = State(initialValue: VendorSearchViewModel(repositories: repositories, vendorId: vendorId))
    }

    var body: some View {
        NavigationStack {
            StateView(
                state: model.state,
                empty: .init(
                    title: "Rien à chercher pour l'instant",
                    systemImage: "magnifyingglass",
                    message: "Ajoute un produit à ton catalogue ou publie un lot : ils apparaîtront ici, avec la demande des quartiers."
                ),
                retry: { await model.load() }
            ) { _ in
                resultsList
            }
            .navigationTitle("Recherche")
            .profileToolbar()
            .sheet(item: $route, onDismiss: { Task { await model.refresh() } }) { route in
                sheet(for: route)
            }
        }
        .searchable(text: $model.query, prompt: "Produit, lot, quartier ou groupe")
        .task { if model.state.value == nil { await model.load() } }
        .sensoryFeedback(.selection, trigger: openedCount)
    }

    // MARK: Résultats

    private var resultsList: some View {
        let results = model.results
        return List {
            if !results.products.isEmpty {
                Section {
                    ForEach(results.products) { product in
                        row(.product(product.id), hint: "Modifie ce produit") {
                            ResultRow(
                                title: product.name,
                                subtitle: "\(product.category.title) · \(product.unit)",
                                subtitleSymbol: "tag.fill"
                            ) {
                                ProductIcon(category: product.category)
                            }
                        }
                    }
                } header: {
                    sectionHeader("Mon catalogue", count: results.products.count, systemImage: "basket.fill")
                }
            }
            if !results.offers.isEmpty {
                Section {
                    ForEach(results.offers) { item in
                        row(.offer(item.offer.id), hint: "Modifie les paliers de ce lot") {
                            ResultRow(
                                title: item.title,
                                subtitle: item.offer.status == .draft
                                    ? String(localized: "\(item.offer.shareUnit) · brouillon")
                                    : String(localized: "\(item.offer.shareUnit) · ferme \(item.offer.deadline.formatted(.relative(presentation: .named).locale(AppLanguage.formattingLocale)))"),
                                subtitleSymbol: item.offer.status == .draft ? "pencil.circle.fill" : "clock.fill"
                            ) {
                                if let category = item.product?.category {
                                    ProductIcon(category: category)
                                } else {
                                    ResultSymbol(systemImage: "shippingbox.fill")
                                }
                            }
                        }
                    }
                } header: {
                    sectionHeader("Mes lots", count: results.offers.count, systemImage: "shippingbox.fill")
                }
            }
            demandSection("Quartiers", points: results.neighborhoods, systemImage: "building.2.fill")
            demandSection("Groupes", points: results.groups, systemImage: "person.3.fill")
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .grenierBackground()
        .refreshable { await model.refresh() }
        .overlay {
            if results.isEmpty {
                ContentUnavailableView {
                    VStack(spacing: 12) {
                        StateIllustration(systemImage: "magnifyingglass")
                            .symbolEffect(.wiggle, value: reduceMotion ? "" : model.query)
                        Text("Aucun résultat")
                            .font(.title2.bold())
                            .foregroundStyle(.texte)
                    }
                } description: {
                    Text("Rien dans ton catalogue, tes lots ou la demande ne correspond à « \(model.query) ».")
                } actions: {
                    Button {
                        model.query = ""
                    } label: {
                        Label("Tout afficher", systemImage: "list.bullet")
                    }
                    .buttonStyle(.glass)
                    .tint(.grenier)
                }
                .grenierTransition(.cardAppear)
            }
        }
        .grenierAnimation(.smooth, value: results)
    }

    @ViewBuilder
    private func demandSection(_ title: LocalizedStringKey, points: [DemandMapViewModel.DemandPoint], systemImage: String) -> some View {
        if !points.isEmpty {
            Section {
                ForEach(points) { point in
                    row(.demand(point), hint: "Affiche la demande de ce point") {
                        ResultRow(title: point.label, subtitle: point.summary, subtitleSymbol: "person.2.fill") {
                            ResultSymbol(systemImage: point.isHighDemand ? "flame.fill" : point.grouping.systemImage)
                        }
                    }
                }
            } header: {
                sectionHeader(title, count: points.count, systemImage: systemImage)
            }
        }
    }

    private func row(_ target: Route, hint: LocalizedStringKey, @ViewBuilder label: () -> some View) -> some View {
        Button {
            openedCount += 1
            route = target
        } label: {
            HStack {
                label()
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.surface)
        .accessibilityHint(hint)
    }

    private func sectionHeader(_ title: LocalizedStringKey, count: Int, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(count, format: .number)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(count)))
        }
        .foregroundStyle(Color.grenier)
        .symbolRenderingMode(.hierarchical)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Feuilles

    @ViewBuilder
    private func sheet(for route: Route) -> some View {
        switch route {
        case .product(let productId):
            ClosableSheet {
                ProductEditorScreen(
                    repositories: repositories, vendorId: vendorId, productId: productId,
                    photoUploader: VendorCatalogSheet.uploader(for: repositories)
                )
            }
        case .offer(let offerId):
            ClosableSheet {
                TierEditorScreen(repositories: repositories, vendorId: vendorId, offerId: offerId)
            }
        case .demand(let point):
            DemandPointSheet(point: point)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Composants

/// Feuille grande avec sa pile de navigation et un bouton Fermer.
private struct ClosableSheet<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer", systemImage: "xmark") { dismiss() }
                    }
                }
        }
        .presentationDetents([.large])
        .presentationBackground(Color.fond)
    }
}

private struct ResultSymbol: View {
    let systemImage: String
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 44

    var body: some View {
        Image(systemName: systemImage)
            .font(.title3)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.grenier)
            .frame(width: min(side, 72), height: min(side, 72))
            .background(Color.grenier.opacity(0.12), in: .rect(cornerRadius: 12))
            .accessibilityHidden(true)
    }
}

private struct ResultRow<Icon: View>: View {
    let title: String
    let subtitle: String
    let subtitleSymbol: String
    @ViewBuilder let icon: () -> Icon

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            icon()
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.texte)
                Label(subtitle, systemImage: subtitleSymbol)
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Clair") {
    VendorSearchScreen(repositories: .fake(), vendorId: FakeData.ID.fermeRive)
}

#Preview("Sombre") {
    VendorSearchScreen(repositories: .fake(data: .demandMapDemo), vendorId: FakeData.ID.fermeRive)
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    VendorSearchScreen(repositories: .fake(), vendorId: FakeData.ID.fermeRive)
        .dynamicTypeSize(.accessibility5)
}
#endif
