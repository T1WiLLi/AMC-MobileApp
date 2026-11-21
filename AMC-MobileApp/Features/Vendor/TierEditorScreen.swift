// TierEditorScreen.swift
// V2 Éditeur de paliers (maquette docs/maquettes/V2-paliers.png) : créer ou modifier un lot et ses paliers de prix.
//
// Poussé dans un NavigationStack (depuis Lots ou Tableau) ; la barre d'onglets se masque.
// Toute la logique (validation, aperçu, revenu, sauvegarde) vient de `TierEditorViewModel` ;
// la vue se contente de dire où est l'erreur et d'y amener la personne.

import Charts
import SwiftUI

struct TierEditorScreen: View {
    @State private var model: TierEditorViewModel
    private let onSaved: ((Offer) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @FocusState private var focus: Field?
    /// Montre les erreurs en rouge : après une première saisie ou une tentative de publication.
    @State private var showsErrors: Bool
    @State private var errorTrigger = 0
    @State private var successTrigger = 0
    @State private var serverError: AppError?

    enum Field: Hashable {
        case totalShares
        case shareUnit
        case threshold(UUID)
        case price(UUID)
    }

    /// Endroit de l'écran où afficher l'erreur de validation courante.
    enum ErrorAnchor: Hashable {
        case product
        case quantity
        case tiers
        case tier(UUID)
        case deadline
    }

    init(
        repositories: AppRepositories = .fake(),
        vendorId: String = FakeData.ID.fermeRive,
        offerId: String? = nil,
        onSaved: ((Offer) -> Void)? = nil
    ) {
        _model = State(initialValue: TierEditorViewModel(repositories: repositories, vendorId: vendorId, offerId: offerId))
        _showsErrors = State(initialValue: false)
        self.onSaved = onSaved
    }

    #if DEBUG
    /// Previews : ViewModel préparé (par exemple une saisie invalide), erreurs visibles.
    init(model: TierEditorViewModel, showsErrors: Bool) {
        _model = State(initialValue: model)
        _showsErrors = State(initialValue: showsErrors)
        self.onSaved = nil
    }
    #endif

    var body: some View {
        StateView(state: model.loadState, retry: { await model.load() }) { _ in
            editor
        }
        .grenierBackground()
        .navigationTitle(model.isEditing ? "Modifier le lot" : "Nouveau lot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .task {
            if case .idle = model.loadState { await model.load() }
        }
        .sensoryFeedback(.error, trigger: errorTrigger)
        .sensoryFeedback(.success, trigger: successTrigger)
        .alert(
            serverError?.title ?? "",
            isPresented: Binding(get: { serverError != nil }, set: { if !$0 { serverError = nil } }),
            presenting: serverError
        ) { error in
            if error.isRetryable {
                Button("Réessayer") { publish() }
            }
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }

    // MARK: Formulaire

    private var editor: some View {
        ScrollViewReader { proxy in
            Form {
                productSection
                tiersSection
                chartSection
                deadlineSection
            }
            .scrollContentBackground(.hidden)
            .symbolRenderingMode(.hierarchical)
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.bottom, 8, for: .scrollContent)
            .safeAreaInset(edge: .bottom) {
                PublishBar(
                    title: model.isEditing ? "Enregistrer le lot" : "Publier le lot",
                    reason: model.validationError?.message,
                    showsReasonAsError: showsErrors,
                    isSaving: model.isSaving,
                    succeeded: successTrigger > 0
                ) {
                    attemptPublish(proxy: proxy)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { focus = nil }
                        .fontWeight(.semibold)
                }
            }
            .onChange(of: focus) { oldValue, _ in
                if oldValue != nil { showsErrors = true }
            }
        }
    }

    // MARK: Produit, quantité, prix épicerie

    private var productSection: some View {
        Section {
            Picker(selection: productBinding) {
                if model.productId == nil {
                    Text("Choisir").tag(String?.none)
                }
                ForEach(model.products) { product in
                    Text(product.name).tag(Optional(product.id))
                }
            } label: {
                Label("Produit", systemImage: "shippingbox.fill")
            }
            .id(ErrorAnchor.product)

            LabeledContent {
                HStack(spacing: 6) {
                    IntegerField(label: "Nombre de parts", value: $model.totalShares)
                        .focused($focus, equals: .totalShares)
                        .fieldBox(isInvalid: isInvalid(.quantity))
                    Text(model.totalShares > 1 ? "parts" : "part")
                        .foregroundStyle(.texteSecondaire)
                }
            } label: {
                Label("Quantité", systemImage: "number.circle.fill")
            }
            .id(ErrorAnchor.quantity)

            LabeledContent {
                TextField("sac de 10 kg", text: $model.shareUnit)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .focused($focus, equals: .shareUnit)
                    .accessibilityLabel("Contenu d'une part")
            } label: {
                Label("Une part", systemImage: "scalemass.fill")
            }

            LabeledContent {
                Text(referencePriceText)
                    .monospacedDigit()
                    .foregroundStyle(.texteSecondaire)
            } label: {
                Label("Prix en épicerie", systemImage: "cart.fill")
            }
            .accessibilityElement(children: .combine)
        } footer: {
            if let message = errorMessage(for: .product) ?? errorMessage(for: .quantity) {
                InlineError(message: message)
            }
        }
        .listRowBackground(Color.surface)
    }

    // MARK: Paliers

    private var tiersSection: some View {
        Section {
            ForEach($model.tiers) { $tier in
                let preview = model.tierPreviews.first { $0.id == tier.id }
                TierRow(
                    tier: $tier,
                    preview: preview,
                    hasReference: model.referenceGroceryPriceCents != nil,
                    isInvalid: isInvalid(.tier(tier.id)),
                    error: errorMessage(for: .tier(tier.id)),
                    focus: $focus
                )
                .id(ErrorAnchor.tier(tier.id))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Supprimer", systemImage: "trash", role: .destructive) {
                        withAnimation(motion) { model.removeTier(id: tier.id) }
                        showsErrors = true
                    }
                }
            }
            .onDelete { offsets in
                withAnimation(motion) { model.removeTiers(atOffsets: offsets) }
                showsErrors = true
            }

            Button {
                withAnimation(motion) { model.addTier() }
                showsErrors = true
                if let last = model.tiers.last { focus = .price(last.id) }
            } label: {
                Label("Ajouter un palier", systemImage: "plus.circle.fill")
                    .symbolEffect(.bounce, value: reduceMotion ? 0 : model.tiers.count)
                    .font(.headline)
                    .frame(minHeight: 44)
            }
            .id(ErrorAnchor.tiers)
        } header: {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    tiersTitle
                    Spacer(minLength: 8)
                    tiersSubtitle
                }
                VStack(alignment: .leading, spacing: 2) {
                    tiersTitle
                    tiersSubtitle
                }
            }
            .textCase(nil)
            .padding(.top, 8)
        } footer: {
            if let message = errorMessage(for: .tiers) {
                InlineError(message: message)
            } else {
                Label("Glisse un palier vers la gauche pour le supprimer.", systemImage: "hand.draw.fill")
                    .font(.footnote)
                    .foregroundStyle(.texteSecondaire)
            }
        }
        .listRowBackground(Color.surface)
    }

    private var tiersTitle: some View {
        Label {
            Text("Paliers de prix")
                .foregroundStyle(.texte)
        } icon: {
            Image(systemName: "stairs")
                .foregroundStyle(Color.grenier)
        }
        .font(.title2.bold())
        .accessibilityAddTraits(.isHeader)
    }

    private var tiersSubtitle: some View {
        Label("plus de parts, prix plus bas", systemImage: "arrow.down.right")
            .labelStyle(TightLabelStyle())
            .font(.subheadline)
            .foregroundStyle(.texteSecondaire)
    }

    // MARK: Graphique

    private var chartSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        chartTitle
                        Spacer(minLength: 8)
                        deadlineCaption
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        chartTitle
                        deadlineCaption
                    }
                }
                TierStepChart(previews: model.tierPreviews, totalShares: model.totalShares)
                revenueText
            }
            .padding(.vertical, 6)
        }
        .listRowBackground(Color.surface)
    }

    private var chartTitle: some View {
        Label {
            Text("Prix selon la demande")
                .foregroundStyle(.texte)
        } icon: {
            Image(systemName: GrenierSymbol.savings)
                .foregroundStyle(Color.grenier)
        }
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
    }

    private var deadlineCaption: some View {
        Label("fermeture \(model.deadline.formatted(.dateTime.weekday(.wide).hour().locale(Self.locale)))", systemImage: "clock.fill")
            .labelStyle(TightLabelStyle())
            .font(.subheadline)
            .foregroundStyle(.texteSecondaire)
    }

    @ViewBuilder
    private var revenueText: some View {
        if let range = model.estimatedRevenueRangeCents {
            let amount = range.lowerBound == range.upperBound
                ? Text(Money.formatRounded(range.lowerBound)).bold()
                : Text("\(Text(Money.formatRounded(range.lowerBound)).bold()) à \(Text(Money.formatRounded(range.upperBound)).bold())")
            Label {
                Text("Revenu estimé : \(amount) pour \(model.totalShares) \(model.totalShares > 1 ? "parts" : "part")")
            } icon: {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundStyle(Color.economie)
                    .symbolEffect(.bounce, value: reduceMotion ? 0 : range.upperBound)
            }
            .font(.subheadline)
            .foregroundStyle(.texteSecondaire)
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(motion, value: range)
        } else {
            Label("Donne un prix à tes paliers pour voir le revenu estimé.", systemImage: "dollarsign.circle")
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
        }
    }

    // MARK: Date limite

    private var deadlineSection: some View {
        Section {
            DatePicker(
                selection: $model.deadline,
                in: Date.now...,
                displayedComponents: [.date, .hourAndMinute]
            ) {
                Label("Date limite", systemImage: "calendar.badge.clock")
            }
            .environment(\.locale, Self.locale)
            .id(ErrorAnchor.deadline)
        } footer: {
            if let message = errorMessage(for: .deadline) {
                InlineError(message: message)
            } else {
                Label("Les familles peuvent prendre une part jusqu'à cette date. Le prix final est celui du palier atteint.", systemImage: "info.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.texteSecondaire)
            }
        }
        .listRowBackground(Color.surface)
    }

    // MARK: Publication

    private func attemptPublish(proxy: ScrollViewProxy) {
        guard model.validationError == nil else {
            showsErrors = true
            errorTrigger += 1
            focus = nil
            if let anchor = errorAnchor {
                withAnimation(motion) { proxy.scrollTo(anchor, anchor: .center) }
                if let error = model.validationError {
                    AccessibilityNotification.Announcement(error.message).post()
                }
            }
            return
        }
        publish()
    }

    private func publish() {
        focus = nil
        Task {
            if let offer = await model.save() {
                successTrigger += 1
                AccessibilityNotification.Announcement(model.isEditing ? "Lot enregistré" : "Lot publié").post()
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 300 : 700))
                onSaved?(offer)
                dismiss()
            } else if let error = model.saveState.error {
                errorTrigger += 1
                if case .invalidInput = error {
                    showsErrors = true
                } else {
                    serverError = error
                }
            }
        }
    }

    // MARK: Erreurs

    /// Où se trouve la première règle non respectée (même ordre que `TierEditorViewModel.validatedOffer()`).
    private var errorAnchor: ErrorAnchor? {
        guard model.validationError != nil else { return nil }
        if model.productId == nil { return .product }
        if model.totalShares <= 0 || model.shareUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .quantity
        }
        guard !model.tiers.isEmpty else { return .tiers }
        for (index, tier) in model.tiers.enumerated() {
            if tier.minShares < 1 || tier.priceCents <= 0 || tier.minShares > model.totalShares { return .tier(tier.id) }
            if index > 0 {
                let previous = model.tiers[index - 1]
                if tier.minShares <= previous.minShares || tier.priceCents >= previous.priceCents { return .tier(tier.id) }
            }
        }
        return .deadline
    }

    private func isInvalid(_ anchor: ErrorAnchor) -> Bool {
        showsErrors && errorAnchor == anchor
    }

    private func errorMessage(for anchor: ErrorAnchor) -> String? {
        guard isInvalid(anchor) else { return nil }
        return model.validationError?.message
    }

    // MARK: Divers

    private static let locale = Locale(identifier: "fr_CA")

    private var motion: Animation? { reduceMotion ? nil : .smooth }

    private var productBinding: Binding<String?> {
        Binding(
            get: { model.productId },
            set: { id in
                if let id { model.selectProduct(id: id) }
            }
        )
    }

    private var referencePriceText: String {
        guard let product = model.selectedProduct else { return "—" }
        return "\(Money.format(product.referenceGroceryPriceCents))/\(product.unit)"
    }
}

// MARK: - Ligne de palier

/// Un palier : rang, seuil éditable, plage couverte, économie vs épicerie, prix éditable.
private struct TierRow: View {
    @Binding var tier: TierEditorViewModel.TierDraft
    let preview: TierEditorViewModel.TierPreview?
    let hasReference: Bool
    let isInvalid: Bool
    let error: String?
    var focus: FocusState<TierEditorScreen.Field?>.Binding

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var badgeSize: CGFloat = 32
    @ScaledMetric(relativeTo: .body) private var priceWidth: CGFloat = 96
    @ScaledMetric(relativeTo: .body) private var thresholdWidth: CGFloat = 48

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            layout {
                HStack(spacing: 12) {
                    rankBadge
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rangeText)
                            .font(.body)
                            .foregroundStyle(.texte)
                            .contentTransition(.numericText())
                        HStack(spacing: 6) {
                            Text("dès")
                                .font(.subheadline)
                                .foregroundStyle(.texteSecondaire)
                            IntegerField(label: "Seuil du palier \(rank)", value: $tier.minShares)
                                .frame(minWidth: thresholdWidth)
                                .focused(focus, equals: .threshold(tier.id))
                                .fieldBox(isInvalid: isInvalid, compact: true)
                            Text(tier.minShares > 1 ? "parts" : "part")
                                .font(.subheadline)
                                .foregroundStyle(.texteSecondaire)
                        }
                    }
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 4) }
                HStack(spacing: 10) {
                    if let preview, preview.savingsPercent > 0 {
                        Label("−\(preview.savingsPercent) %", systemImage: "arrow.down.circle.fill")
                            .labelStyle(TightLabelStyle())
                            .font(.subheadline.bold())
                            .fontDesign(.rounded)
                            .monospacedDigit()
                            .foregroundStyle(.economie)
                            .contentTransition(.numericText())
                            .accessibilityLabel("\(preview.savingsPercent) pour cent moins cher qu'en épicerie")
                    } else if hasReference, tier.priceCents > 0 {
                        Label("aucune économie", systemImage: "equal.circle")
                            .labelStyle(TightLabelStyle())
                            .font(.caption)
                            .foregroundStyle(.texteSecondaire)
                    }
                    PriceField(label: "Prix du palier \(rank)", value: $tier.price)
                        .frame(minWidth: priceWidth)
                        .focused(focus, equals: .price(tier.id))
                        .fieldBox(isInvalid: isInvalid)
                }
            }
            if let error {
                InlineError(message: error)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .animation(.smooth, value: error)
    }

    private var rank: Int { preview?.rank ?? 1 }

    private var rankBadge: some View {
        Text("\(rank)")
            .font(.headline)
            .fontDesign(.rounded)
            .foregroundStyle(isInvalid ? Color.red : Color.grenier)
            .frame(width: badgeSize, height: badgeSize)
            .background((isInvalid ? Color.red : Color.grenier).opacity(0.12), in: .circle)
            .accessibilityLabel("Palier \(rank)")
    }

    private var rangeText: String {
        guard let preview else { return "" }
        let unit = (preview.maxShares ?? preview.minShares) > 1 ? "parts" : "part"
        guard let max = preview.maxShares else { return "\(preview.minShares) \(unit) et +" }
        if max <= preview.minShares { return "\(preview.minShares) \(unit)" }
        return "\(preview.minShares) à \(max) \(unit)"
    }
}

// MARK: - Graphique en escalier

/// Prix par part selon le nombre de parts engagées (escalier : le prix tombe à chaque seuil).
private struct TierStepChart: View {
    let previews: [TierEditorViewModel.TierPreview]
    let totalShares: Int

    @ScaledMetric(relativeTo: .caption) private var chartHeight: CGFloat = 150

    private struct Step: Identifiable {
        let id: Int
        let shares: Int
        let price: Double
    }

    /// Paliers valides triés, plus un point final au total du lot pour dessiner la dernière marche.
    private var steps: [Step] {
        let valid = previews.filter { $0.priceCents > 0 && $0.minShares >= 1 }.sorted { $0.minShares < $1.minShares }
        var result = valid.enumerated().map { Step(id: $0.offset, shares: $0.element.minShares, price: Double($0.element.priceCents) / 100) }
        if let last = result.last {
            let end = max(totalShares, last.shares + max(1, last.shares / 4))
            result.append(Step(id: result.count, shares: end, price: last.price))
        }
        return result
    }

    var body: some View {
        if steps.count < 2 {
            Label("Le graphique apparaît dès qu'un palier a un prix.", systemImage: GrenierSymbol.savings)
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .symbolRenderingMode(.hierarchical)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            Chart {
                ForEach(steps) { step in
                    LineMark(x: .value("Parts", step.shares), y: .value("Prix", step.price))
                        .interpolationMethod(.stepEnd)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(Color.grenier)
                }
                if steps.count > 2, let last = steps.dropLast().last {
                    PointMark(x: .value("Parts", last.shares), y: .value("Prix", last.price))
                        .foregroundStyle(Color.grenier)
                        .symbolSize(60)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: steps.dropLast().map(\.price)) { value in
                    AxisValueLabel {
                        if let price = value.as(Double.self) {
                            Text(price, format: .number.precision(.fractionLength(2)).locale(Locale(identifier: "fr_CA")))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: steps.dropFirst().dropLast().map(\.shares)) { value in
                    AxisValueLabel()
                }
            }
            .chartXAxisLabel("parts", position: .bottomTrailing)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: chartHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Graphique du prix selon la demande")
            .accessibilityValue(summary)
        }
    }

    private var summary: String {
        previews.filter { $0.priceCents > 0 }.map { preview in
            let range = preview.maxShares.map { "de \(preview.minShares) à \($0) parts" } ?? "à partir de \(preview.minShares) parts"
            return "\(range), \(Money.format(preview.priceCents)) la part"
        }
        .joined(separator: " ; ")
    }
}

// MARK: - Barre du bas

/// Barre « Publier le lot » : seule action principale, raison lisible quand le lot n'est pas publiable.
private struct PublishBar: View {
    let title: String
    let reason: String?
    let showsReasonAsError: Bool
    let isSaving: Bool
    let succeeded: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let reason {
                Label(reason, systemImage: showsReasonAsError ? "exclamationmark.circle.fill" : "info.circle")
                    .font(.footnote)
                    .foregroundStyle(showsReasonAsError ? Color.red : Color.texteSecondaire)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(3)
                    .accessibilityHidden(true)
            }
            Button(action: action) {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .tint(.onAccent)
                    } else if succeeded {
                        Image(systemName: "checkmark.seal.fill")
                            .symbolEffect(.bounce, value: succeeded)
                    }
                    Text(succeeded ? "Publié !" : title)
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.grenier.opacity(reason == nil ? 1 : 0.45))
            .controlSize(.large)
            .allowsHitTesting(!isSaving && !succeeded)
            .accessibilityLabel(title)
            .accessibilityValue(reason == nil ? "" : "Indisponible")
            .accessibilityHint(reason.map { "Pour publier : \($0)" } ?? "Publie le lot pour les groupes de ton secteur.")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background {
            // Fondu vers le fond crème pour que le texte reste lisible au-dessus du formulaire.
            LinearGradient(colors: [Color.fond.opacity(0), Color.fond], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        }
    }
}

// MARK: - Champs et erreurs

/// Message d'erreur sous un champ ou une section.
private struct InlineError: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.red)
            .symbolRenderingMode(.hierarchical)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Erreur : \(message)")
    }
}

/// Champ entier (pavé numérique) qui met à jour la valeur à chaque frappe, pour une validation en direct.
private struct IntegerField: View {
    let label: String
    @Binding var value: Int
    @State private var text = ""

    var body: some View {
        TextField(label, text: $text, prompt: Text("0"))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .accessibilityLabel(label)
            .onAppear { text = value == 0 ? "" : String(value) }
            .onChange(of: text) { _, newText in
                let digits = newText.filter(\.isNumber)
                if digits != newText { text = digits }
                value = Int(digits.prefix(6)) ?? 0
            }
            .onChange(of: value) { _, newValue in
                if (Int(text) ?? 0) != newValue { text = newValue == 0 ? "" : String(newValue) }
            }
    }
}

/// Champ de prix en dollars (pavé décimal, virgule ou point) mis à jour à chaque frappe.
private struct PriceField: View {
    let label: String
    @Binding var value: Decimal
    @State private var text = ""

    private static let locale = Locale(identifier: "fr_CA")

    var body: some View {
        HStack(spacing: 4) {
            TextField(label, text: $text, prompt: Text("0,00"))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .priceStyle(.headline)
                .accessibilityLabel(label)
                .accessibilityValue(value > 0 ? Money.format(Self.cents(value)) : "vide")
            Text("$")
                .font(.headline)
                .fontDesign(.rounded)
                .foregroundStyle(.texte)
                .accessibilityHidden(true)
        }
        .onAppear { text = Self.format(value) }
        .onChange(of: text) { _, newText in
            let cleaned = Self.clean(newText)
            if cleaned != newText { text = cleaned; return }
            value = Self.parse(cleaned)
        }
        .onChange(of: value) { _, newValue in
            if Self.parse(text) != newValue { text = Self.format(newValue) }
        }
    }

    /// Garde chiffres et un seul séparateur décimal, deux décimales au plus.
    private static func clean(_ text: String) -> String {
        var result = ""
        var hasSeparator = false
        var decimals = 0
        for character in text {
            if character.isNumber {
                if hasSeparator {
                    guard decimals < 2 else { continue }
                    decimals += 1
                }
                result.append(character)
            } else if (character == "," || character == "."), !hasSeparator {
                hasSeparator = true
                result.append(",")
            }
        }
        return String(result.prefix(8))
    }

    private static func parse(_ text: String) -> Decimal {
        Decimal(string: text.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    private static func format(_ value: Decimal) -> String {
        guard value > 0 else { return "" }
        return value.formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(locale))
    }

    private static func cents(_ value: Decimal) -> Cents {
        NSDecimalNumber(decimal: value * 100).intValue
    }
}

private extension View {
    /// Boîte de saisie de la maquette (fond crème, bordure fine) ; rouge si le champ est fautif.
    func fieldBox(isInvalid: Bool, compact: Bool = false) -> some View {
        padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, compact ? 6 : 10)
            .frame(minHeight: 44)
            .background(Color.fond, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isInvalid ? Color.red : Color.piste, lineWidth: isInvalid ? 2 : 1)
            }
            .animation(.smooth, value: isInvalid)
    }
}

// MARK: - Previews

#if DEBUG
private extension TierEditorViewModel {
    /// Lot de démo « paliers dans le désordre et prix qui remonte » pour la preview de saisie invalide.
    static func invalidSample() -> TierEditorViewModel {
        let model = TierEditorViewModel(repositories: .fake(behavior: .instant), vendorId: FakeData.ID.fermeRive)
        model.tiers = [
            .init(minShares: 1, priceCents: 1_350),
            .init(minShares: 20, priceCents: 1_150),
            .init(minShares: 12, priceCents: 1_290),
        ]
        model.totalShares = 40
        return model
    }
}
#endif

#Preview("Nouveau lot") {
    NavigationStack {
        TierEditorScreen(repositories: .fake())
    }
}

#Preview("Modification sombre") {
    NavigationStack {
        TierEditorScreen(repositories: .fake(), offerId: FakeData.ID.potatoOffer)
    }
    .preferredColorScheme(.dark)
}

#Preview("AX5") {
    NavigationStack {
        TierEditorScreen(repositories: .fake(), offerId: FakeData.ID.potatoOffer)
    }
    .dynamicTypeSize(.accessibility5)
}

#Preview("Saisie invalide") {
    NavigationStack {
        TierEditorScreen(model: .invalidSample(), showsErrors: true)
    }
}
