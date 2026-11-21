import SwiftUI

/// Planificateur de besoins du mois (T-105, RQ-099, RQ-100) : budget au Slider, besoins du ménage,
/// et lots du groupe proposés pour les couvrir, avec l'économie et le budget utilisé.
/// Poussé depuis le Profil (« Planifier mon mois ») ; enregistre le plan sur l'appareil.
struct NeedsPlannerScreen: View {
    @Environment(\.appContext) private var context
    @State private var viewModel: NeedsPlannerViewModel?
    /// Injecté par les previews et les tests ; sinon `UserDefaults`.
    var store: any NeedsPlanStore = UserDefaultsNeedsPlanStore()

    var body: some View {
        Group {
            if let viewModel {
                NeedsPlannerContent(viewModel: viewModel)
            } else {
                ProgressView("Chargement…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .grenierBackground()
            }
        }
        .navigationTitle("Mon mois")
        .navigationBarTitleDisplayMode(.large)
        .offerDestination()
        .task {
            guard viewModel == nil else { return }
            let model = NeedsPlannerViewModel(
                repositories: context.repositories, householdId: context.householdId,
                groupId: context.groupId, store: store
            )
            viewModel = model
            await model.load()
        }
    }
}

// MARK: - Contenu

private struct NeedsPlannerContent: View {
    @Bindable var viewModel: NeedsPlannerViewModel
    @State private var isAddingNeed = false
    @State private var addedCount = 0

    var body: some View {
        let result = viewModel.result
        List {
            Section {
                BudgetCard(viewModel: viewModel, result: result)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section {
                if viewModel.needs.isEmpty {
                    Label("Ajoute ce dont ton ménage a besoin ce mois-ci.", systemImage: "list.bullet.clipboard")
                        .foregroundStyle(.texteSecondaire)
                        .symbolRenderingMode(.hierarchical)
                }
                ForEach(viewModel.needs) { need in
                    NeedRow(need: need, coverage: viewModel.coverage(of: need),
                            isUnmatched: viewModel.catalog.value != nil && viewModel.isUnmatched(need))
                        .swipeActions {
                            Button("Retirer", systemImage: "trash", role: .destructive) {
                                withAnimation(.smooth) { viewModel.removeNeed(id: need.id) }
                            }
                        }
                }
                .onDelete { offsets in
                    withAnimation(.smooth) { viewModel.removeNeeds(at: offsets) }
                }
                Button {
                    isAddingNeed = true
                } label: {
                    Label("Ajouter un besoin", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .symbolRenderingMode(.hierarchical)
                        .symbolEffect(.bounce, value: addedCount)
                }
                .foregroundStyle(Color.grenier)
            } header: {
                Label("Mes besoins", systemImage: "cart.fill")
            } footer: {
                Text("Glisse une ligne vers la gauche pour la retirer.")
            }

            Section {
                SuggestionsSection(viewModel: viewModel, result: result)
            } header: {
                Label("Lots suggérés", systemImage: "sparkles")
            } footer: {
                Text("Classés selon tes besoins, l'économie vs l'épicerie, ton budget et la date limite.")
            }
        }
        .scrollContentBackground(.hidden)
        .grenierBackground()
        .refreshable { await viewModel.load() }
        .grenierHaptic(.success, trigger: addedCount)
        .sheet(isPresented: $isAddingNeed) {
            AddNeedSheet(products: viewModel.products) { target, quantity, unit in
                withAnimation(.smooth) { viewModel.addNeed(target, quantity: quantity, unit: unit) }
                addedCount += 1
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Ajouter un besoin", systemImage: "plus") { isAddingNeed = true }
            }
        }
    }
}

// MARK: - Budget

private struct BudgetCard: View {
    @Bindable var viewModel: NeedsPlannerViewModel
    let result: NeedsPlanResult

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Budget du mois", systemImage: "wallet.bifold.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.texteSecondaire)
                .symbolRenderingMode(.hierarchical)

            Text(Money.formatRounded(viewModel.budgetCents))
                .font(.largeTitle.bold())
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(.texte)
                .contentTransition(.numericText(value: Double(viewModel.budgetCents)))
                .animation(reduceMotion ? nil : .smooth, value: viewModel.budgetCents)

            Slider(value: $viewModel.budgetDollars, in: NeedsPlannerViewModel.budgetRange, step: 5) {
                Text("Budget du mois")
            } minimumValueLabel: {
                Image(systemName: "minus").accessibilityHidden(true)
            } maximumValueLabel: {
                Image(systemName: "plus").accessibilityHidden(true)
            }
            .tint(Color.grenier)
            .accessibilityValue(Money.formatRounded(viewModel.budgetCents))
            .sensoryFeedback(.selection, trigger: viewModel.budgetCents)

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: result.budgetUsage)
                    .tint(result.budgetUsage >= 1 ? Color.solidarite : Color.grenier)
                    .animation(reduceMotion ? nil : .smooth, value: result.budgetUsage)
                    .accessibilityHidden(true)
                Text("\(Money.formatRounded(result.usedBudgetCents)) utilisés · reste \(Money.formatRounded(result.remainingBudgetCents))")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.texteSecondaire)
                    .contentTransition(.numericText(value: Double(result.usedBudgetCents)))
                    .animation(reduceMotion ? nil : .smooth, value: result.usedBudgetCents)
            }

            Divider().overlay(Color.piste)

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            layout {
                Image(systemName: GrenierSymbol.savings)
                    .font(.title3.bold())
                    .foregroundStyle(Color.economie)
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.bounce, value: result.savingsCents)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Money.formatRounded(result.savingsCents))
                        .priceStyle(.title2.bold())
                        .foregroundStyle(Color.economie)
                        .contentTransition(.numericText(value: Double(result.savingsCents)))
                        .animation(reduceMotion ? nil : .smooth, value: result.savingsCents)
                    Text("d'économie prévue vs l'épicerie")
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                CoverageRing(value: result.overallCoverage)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Money.formatRounded(result.savingsCents)) d'économie prévue, besoins couverts à \(Int((result.overallCoverage * 100).rounded())) %")
        }
        .grenierCard(padding: 20)
    }
}

/// Anneau « besoins couverts à 80 % ».
private struct CoverageRing: View {
    let value: Double
    @ScaledMetric(relativeTo: .title3) private var side: CGFloat = 52
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(Color.piste, lineWidth: 6)
            Circle()
                .trim(from: 0, to: value)
                .stroke(Color.economie, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .smooth, value: value)
            Text("\(Int((value * 100).rounded())) %")
                .font(.caption.bold())
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(.texte)
                .contentTransition(.numericText(value: value))
                .minimumScaleFactor(0.6)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

// MARK: - Besoins

private struct NeedRow: View {
    let need: NeedItem
    let coverage: Double
    let isUnmatched: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            ProductIcon(category: need.target.category)
            VStack(alignment: .leading, spacing: 4) {
                Text(need.target.title)
                    .font(.headline)
                    .foregroundStyle(.texte)
                Text(NeedFormat.quantity(need.quantity, need.unit))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.texteSecondaire)
                if isUnmatched {
                    Label("Aucun lot ouvert pour l'instant", systemImage: "clock.badge.questionmark")
                        .font(.caption)
                        .foregroundStyle(.texteSecondaire)
                        .symbolRenderingMode(.hierarchical)
                } else {
                    ProgressView(value: coverage)
                        .tint(Color.economie)
                        .animation(reduceMotion ? nil : .smooth, value: coverage)
                        .accessibilityHidden(true)
                }
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            if !isUnmatched {
                Image(systemName: coverage >= 1 ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.title3)
                    .foregroundStyle(coverage >= 1 ? Color.economie : Color.secondary)
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isUnmatched
            ? String(localized: "Aucun lot ouvert")
            : String(localized: "Couvert à \(Int((coverage * 100).rounded())) %"))
    }
}

// MARK: - Suggestions

private struct SuggestionsSection: View {
    let viewModel: NeedsPlannerViewModel
    let result: NeedsPlanResult

    var body: some View {
        switch viewModel.catalog {
        case .idle, .loading:
            ForEach(0..<3, id: \.self) { _ in
                SuggestionRow(suggestion: .placeholder, needTitle: String(localized: "Céréales"))
                    .redacted(reason: .placeholder)
            }
            .accessibilityLabel("Chargement des lots")
        case .failed(let error):
            ContentUnavailableView {
                Label("Lots indisponibles", systemImage: "wifi.exclamationmark")
                    .symbolRenderingMode(.hierarchical)
            } description: {
                Text(error.message)
            } actions: {
                Button("Réessayer", systemImage: "arrow.clockwise") {
                    Task { await viewModel.load() }
                }
                .buttonStyle(.glass)
            }
        case .empty, .loaded:
            if result.suggestions.isEmpty {
                ContentUnavailableView {
                    Label("Aucun lot à suggérer", systemImage: "shippingbox.and.arrow.backward")
                        .symbolRenderingMode(.hierarchical)
                } description: {
                    Text(viewModel.needs.isEmpty
                         ? String(localized: "Ajoute un besoin pour voir les lots qui y répondent.")
                         : String(localized: "Aucun lot ouvert ne répond à tes besoins pour l'instant. Reviens dans quelques jours."))
                }
            } else {
                ForEach(result.suggestions) { suggestion in
                    NavigationLink(value: OfferRoute(offerId: suggestion.offer.id)) {
                        SuggestionRow(suggestion: suggestion,
                                      needTitle: viewModel.need(id: suggestion.needId)?.target.title ?? "")
                    }
                }
            }
        }
    }
}

private struct SuggestionRow: View {
    let suggestion: LotSuggestion
    let needTitle: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            ProductIcon(category: suggestion.product.category)
            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.product.name)
                    .font(.headline)
                    .foregroundStyle(.texte)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                Label(deadline, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.texteSecondaire)
                    .symbolRenderingMode(.hierarchical)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
                if suggestion.fitsBudget {
                    Text(Money.formatRounded(suggestion.costCents))
                        .priceStyle(.headline)
                        .foregroundStyle(.texte)
                        .contentTransition(.numericText(value: Double(suggestion.costCents)))
                    if suggestion.savingsCents > 0 {
                        SavingsBadge(kind: .amount(suggestion.savingsCents), compact: true)
                    }
                } else {
                    Label("Hors budget", systemImage: "exclamationmark.circle")
                        .font(.caption.bold())
                        .foregroundStyle(Color.solidarite)
                        .symbolRenderingMode(.hierarchical)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(suggestion.fitsBudget ? 1 : 0.7)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvre la fiche du lot.")
    }

    /// « 2 parts · sac de 10 kg · pour Céréales »
    private var detail: String {
        let shares = suggestion.fitsBudget ? suggestion.shares : suggestion.sharesToCoverNeed
        let part = shares > 1 ? "parts" : "part"
        let base = "\(shares) \(part) · \(suggestion.offer.shareUnit)"
        return needTitle.isEmpty ? base : String(localized: "\(base) · pour \(needTitle)")
    }

    private var deadline: String {
        let date = suggestion.offer.deadline.formatted(.dateTime.weekday(.wide).day().month().locale(Locale(identifier: "fr_CA")))
        return String(localized: "Ferme \(date)")
    }
}

private extension LotSuggestion {
    /// Ligne fictive pour le squelette de chargement.
    static let placeholder = LotSuggestion(
        offer: Offer(id: "placeholder", vendorId: "", productId: "", totalShares: 10, shareUnit: "sac de 10 kg",
                     tiers: [], minimumSharesToLaunch: 1, deadline: .now, zones: [], status: .active),
        product: Product(id: "", vendorId: "", name: "Riz basmati", category: .grains, unit: "kg", origin: "",
                         tags: [], photoURL: nil, referenceGroceryPriceCents: 0),
        needId: UUID(), shares: 1, sharesToCoverNeed: 1, unitPriceCents: 2_000, savingsPercent: 20,
        costCents: 2_000, savingsCents: 500, coveredQuantity: 10, score: 0
    )
}

// MARK: - Ajout d'un besoin

private struct AddNeedSheet: View {
    let products: [Product]
    let onAdd: (NeedItem.Target, Double, NeedUnit) -> Void

    private enum Kind: String, CaseIterable, Identifiable {
        case category, product
        var id: Self { self }
        var title: String { self == .category ? String(localized: "Catégorie") : String(localized: "Produit") }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind = .category
    @State private var category: Product.Category = .grains
    @State private var productId: String?
    @State private var quantity: Double = 10
    @State private var unit: NeedUnit = .kilograms

    var body: some View {
        NavigationStack {
            Form {
                if !products.isEmpty {
                    Picker("Besoin", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    switch kind {
                    case .category:
                        Picker("Catégorie", selection: $category) {
                            ForEach(Product.Category.allCases, id: \.self) { item in
                                Label(item.title, systemImage: ProductIcon.symbol(for: item)).tag(item)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    case .product:
                        Picker("Produit", selection: $productId) {
                            Text("Choisir…").tag(String?.none)
                            ForEach(products) { product in
                                Label(product.name, systemImage: ProductIcon.symbol(for: product.category))
                                    .tag(Optional(product.id))
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                } header: {
                    Label("Quoi", systemImage: "basket.fill")
                }

                Section {
                    Picker("Unité", selection: $unit) {
                        ForEach(NeedUnit.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Stepper(value: $quantity, in: 1...200, step: 1) {
                        Text(NeedFormat.quantity(quantity, unit))
                            .font(.headline)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: quantity))
                    }
                    .sensoryFeedback(.selection, trigger: quantity)
                } header: {
                    Label("Combien ce mois-ci", systemImage: "scalemass.fill")
                }
            }
            .navigationTitle("Nouveau besoin")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: category) { _, new in unit = NeedFormat.defaultUnit(for: new) }
            .onChange(of: productId) { _, new in
                if let product = products.first(where: { $0.id == new }) {
                    unit = NeedFormat.defaultUnit(for: product.category)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter", systemImage: "checkmark") {
                        guard let target else { return }
                        onAdd(target, quantity, unit)
                        dismiss()
                    }
                    .disabled(target == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var target: NeedItem.Target? {
        switch kind {
        case .category:
            return .category(category)
        case .product:
            guard let product = products.first(where: { $0.id == productId }) else { return nil }
            return .product(id: product.id, name: product.name, category: product.category)
        }
    }
}

// MARK: - Formats

enum NeedFormat {
    /// « 10 kg », « 2,5 L », « 12 unités ».
    static func quantity(_ value: Double, _ unit: NeedUnit) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "fr_CA")))
        if unit == .units { return "\(number) \(value > 1 ? "unités" : "unité")" }
        return "\(number) \(unit.symbol)"
    }

    /// Unité la plus naturelle pour une catégorie.
    static func defaultUnit(for category: Product.Category) -> NeedUnit {
        switch category {
        case .oils: .liters
        case .eggs, .canned, .household: .units
        default: .kilograms
        }
    }
}

// MARK: - Previews

#Preview("Clair") {
    NavigationStack {
        NeedsPlannerScreen(store: InMemoryNeedsPlanStore())
    }
    .environment(\.appContext, .instant)
}

#Preview("Sombre") {
    NavigationStack {
        NeedsPlannerScreen(store: InMemoryNeedsPlanStore())
    }
    .environment(\.appContext, .instant)
    .preferredColorScheme(.dark)
}

#Preview("AX5") {
    NavigationStack {
        NeedsPlannerScreen(store: InMemoryNeedsPlanStore())
    }
    .environment(\.appContext, .instant)
    .dynamicTypeSize(.accessibility5)
}
