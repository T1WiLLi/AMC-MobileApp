import SwiftUI

/// Fiche d'un lot et choix de sa part (maquette F3), puis « Palier débloqué ! » (maquette F4).
///
/// Lit `@Environment(\.appContext)` pour les dépôts, le ménage et le groupe, et pilote `OfferDetailViewModel`.
struct OfferDetailScreen: View {
    let offerId: String
    @Environment(\.appContext) private var context
    @State private var viewModel: OfferDetailViewModel?

    var body: some View {
        Group {
            if let viewModel {
                OfferDetailContent(viewModel: viewModel)
            } else {
                ProgressView("Chargement…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .grenierBackground()
            }
        }
        .toolbarVisibility(.hidden, for: .tabBar)
        .task {
            if viewModel == nil {
                viewModel = OfferDetailViewModel(
                    repositories: context.repositories,
                    offerId: offerId,
                    householdId: context.householdId,
                    groupId: context.groupId
                )
            }
        }
    }
}

// MARK: - F3 Fiche du lot

private struct OfferDetailContent: View {
    @Bindable var viewModel: OfferDetailViewModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var heroSymbolSize: CGFloat = 96
    @ScaledMetric(relativeTo: .largeTitle) private var heroHeight: CGFloat = 260
    /// Dernière célébration montrée, gardée pendant l'animation de fermeture de la feuille.
    @State private var shownCelebration: OfferDetailViewModel.TierCelebration?

    var body: some View {
        StateView(
            state: viewModel.state,
            empty: .init(title: "Lot introuvable", systemImage: "shippingbox", message: "Ce lot n'est plus disponible."),
            retry: { await viewModel.load() }
        ) { content in
            loaded(content)
        }
        .grenierBackground()
        .navigationTitle(viewModel.state.value?.product.name ?? "Lot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let content = viewModel.state.value {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareText(content)) {
                        Label("Partager le lot", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .task {
            await viewModel.load()
            await viewModel.observe()
        }
        .alert(
            viewModel.actionError?.title ?? "",
            isPresented: errorPresented,
            presenting: viewModel.actionError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
        .sheet(isPresented: celebrationPresented) {
            celebrationSheet
        }
        .onChange(of: viewModel.celebration) { _, newValue in
            if let newValue { shownCelebration = newValue }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: myShareQuantity) { (old: Int?, new: Int?) -> Bool in
            guard let old, let new else { return false }
            return old != new
        }
    }

    /// Quantité réservée par le ménage, `nil` tant que le lot n'est pas chargé (déclencheur de l'haptique).
    private var myShareQuantity: Int? {
        viewModel.state.value?.myShareQuantity
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.actionError != nil },
            set: { if !$0 { viewModel.actionError = nil } }
        )
    }

    private var celebrationPresented: Binding<Bool> {
        Binding(
            get: { viewModel.celebration != nil },
            set: { if !$0 { viewModel.dismissCelebration() } }
        )
    }

    @ViewBuilder
    private var celebrationSheet: some View {
        if let celebration = viewModel.celebration ?? shownCelebration, let content = viewModel.state.value {
            TierCelebrationView(
                celebration: celebration,
                tiers: content.offer.tiers,
                totalShares: content.offer.totalShares,
                shareUnit: content.offer.shareUnit,
                onDone: { viewModel.dismissCelebration() }
            )
        }
    }

    // MARK: Contenu

    private func loaded(_ content: OfferDetailViewModel.Content) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                hero(content)
                VStack(alignment: .leading, spacing: 24) {
                    header(content)
                    priceRow(content)
                    tiersCard(content)
                    shareSection(content)
                }
                .padding(.horizontal, 16)
                .padding(.top, 28)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.fond,
                    in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                )
                .padding(.top, -32)
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            reserveBar(content)
        }
    }

    private func hero(_ content: OfferDetailViewModel.Content) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color.grenier.opacity(0.22), Color.grenier.opacity(0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
            .backgroundExtensionEffect()
            Image(systemName: ProductIcon.symbol(for: content.product.category))
                .font(.system(size: heroSymbolSize, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .padding(.top, 40)
        }
        .frame(height: heroHeight)
        .accessibilityHidden(true)
    }

    private func header(_ content: OfferDetailViewModel.Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(content.vendor.legalName) · \(content.product.origin)")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(Color.grenier)
            Text(content.product.name)
                .font(.title2.bold())
                .foregroundStyle(.texte)
                .accessibilityAddTraits(.isHeader)
            Text("Commande groupée · \(content.offer.shareUnit) · ferme \(Self.deadlineText(content.offer.deadline))")
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
        }
        .accessibilityElement(children: .combine)
    }

    private func priceRow(_ content: OfferDetailViewModel.Content) -> some View {
        let pricing = content.pricing
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .lastTextBaseline, spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                PriceTag(priceCents: pricing.currentPriceCents, referenceCents: pricing.groceryPriceCents)
                Text("prix du \(content.offer.shareUnit)")
                    .font(.caption)
                    .foregroundStyle(.texteSecondaire)
                    .accessibilityHidden(true)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            if pricing.savingsPercent > 0 {
                SavingsBadge(kind: .percent(pricing.savingsPercent))
            }
        }
    }

    private func tiersCard(_ content: OfferDetailViewModel.Content) -> some View {
        let pricing = content.pricing
        let households = content.groupOrder?.committedHouseholds ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    progressTitle(households: households, content: content)
                    Spacer(minLength: 8)
                    tierCaption(pricing)
                }
                VStack(alignment: .leading, spacing: 4) {
                    progressTitle(households: households, content: content)
                    tierCaption(pricing)
                }
            }
            TierProgressBar(
                tiers: content.offer.tiers,
                committedShares: content.committedShares,
                totalShares: content.offer.totalShares
            )
            if content.groupOrder == nil {
                Label("Ton groupe n'a pas encore lancé de commande sur ce lot.", systemImage: "person.3.fill")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .symbolRenderingMode(.hierarchical)
            } else if !content.isOpen {
                Label("La commande est fermée : les parts ne bougent plus.", systemImage: "clock.badge.xmark")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .grenierCard()
    }

    private func progressTitle(households: Int, content: OfferDetailViewModel.Content) -> some View {
        Text("\(households) \(households > 1 ? "familles" : "famille") · \(content.committedShares) parts sur \(content.offer.totalShares)")
            .font(.headline)
            .foregroundStyle(.texte)
            .monospacedDigit()
            .contentTransition(.numericText())
    }

    private func tierCaption(_ pricing: OfferPricing) -> some View {
        Text(pricing.tierNumber == 0 ? "Avant le 1er palier" : "Palier \(pricing.tierNumber) sur \(pricing.tierCount)")
            .font(.subheadline)
            .foregroundStyle(.texteSecondaire)
    }

    @ViewBuilder
    private func shareSection(_ content: OfferDetailViewModel.Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ta part")
                .font(.title3.bold())
                .foregroundStyle(.texte)
                .accessibilityAddTraits(.isHeader)

            if viewModel.quantityOptions.isEmpty {
                Text("Il ne reste plus de parts dans ce lot.")
                    .font(.body)
                    .foregroundStyle(.texteSecondaire)
            } else {
                sharePicker(content)

                if viewModel.selectedSavingsCents > 0 {
                    Text("Tu économises \(Text(Money.formatRounded(viewModel.selectedSavingsCents)).foregroundStyle(Color.economie).bold()) sur ta part.")
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                        .contentTransition(.numericText())
                }
                if viewModel.selectionUnlocksTier {
                    Label("Ta part fait tomber le prochain palier pour tout le groupe !", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.grenier)
                        .symbolRenderingMode(.hierarchical)
                }
            }

            if content.myShareQuantity > 0 {
                HStack(alignment: .firstTextBaseline) {
                    Label(
                        "Tu as réservé \(Self.quantityLabel(content.myShareQuantity, shareUnit: content.offer.shareUnit)).",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.texte)
                    .symbolRenderingMode(.hierarchical)
                    Spacer(minLength: 0)
                }
                if content.isOpen {
                    Button(role: .destructive) {
                        Task { await viewModel.cancelShare() }
                    } label: {
                        Label("Annuler ma part", systemImage: "xmark.circle")
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.glass)
                    .disabled(viewModel.isSaving)
                }
            }
        }
    }

    @ViewBuilder
    private func sharePicker(_ content: OfferDetailViewModel.Content) -> some View {
        let picker = Picker("Ta part", selection: $viewModel.selectedQuantity) {
            ForEach(viewModel.quantityOptions, id: \.self) { quantity in
                Text(Self.quantityLabel(quantity, shareUnit: content.offer.shareUnit)).tag(quantity)
            }
        }
        if dynamicTypeSize.isAccessibilitySize {
            picker
                .pickerStyle(.menu)
                .tint(Color.grenier)
        } else {
            picker
                .pickerStyle(.segmented)
                .controlSize(.large)
        }
    }

    // MARK: Barre du bas

    private func reserveBar(_ content: OfferDetailViewModel.Content) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        let quantity = Self.quantityLabel(viewModel.selectedQuantity, shareUnit: content.offer.shareUnit)
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(Money.format(viewModel.selectedTotalCents))
                    .priceStyle(.title2.bold())
                    .foregroundStyle(.texte)
                    .contentTransition(.numericText(value: Double(viewModel.selectedTotalCents)))
                Text("\(quantity) · payé à la cueillette")
                    .font(.footnote)
                    .foregroundStyle(.texteSecondaire)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Total \(Money.format(viewModel.selectedTotalCents)) pour \(quantity), payé à la cueillette")

            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }

            Button {
                Task { await viewModel.reserve() }
            } label: {
                Group {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Text(reserveTitle(content, quantity: quantity))
                            .multilineTextAlignment(.center)
                    }
                }
                .font(.headline)
                .frame(minHeight: 32)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                .padding(.horizontal, 8)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(Color.grenier)
            .disabled(!viewModel.canReserve)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .animation(.smooth, value: viewModel.selectedQuantity)
    }

    private func reserveTitle(_ content: OfferDetailViewModel.Content, quantity: String) -> String {
        if content.myShareQuantity == 0 { return "Réserver \(quantity)" }
        if content.myShareQuantity == viewModel.selectedQuantity { return "Part réservée" }
        return "Passer à \(quantity)"
    }

    private func shareText(_ content: OfferDetailViewModel.Content) -> String {
        "\(content.product.name) (\(content.offer.shareUnit)) à \(Money.format(content.pricing.currentPriceCents)) avec \(content.vendor.legalName) sur Grenier. Plus on est de familles, plus le prix baisse !"
    }

    // MARK: Formatage

    static func deadlineText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).hour().locale(Locale(identifier: "fr_CA")))
    }

    /// « 20 kg » pour 2 parts de « sac de 10 kg » ; sinon « 2 × caisse ».
    static func quantityLabel(_ shares: Int, shareUnit: String) -> String {
        if let match = shareUnit.firstMatch(of: /(\d+(?:[.,]\d+)?)\s*(kg|g|L|l)\b/),
           let value = Double(match.1.replacingOccurrences(of: ",", with: ".")) {
            let total = value * Double(shares)
            let number = total.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "fr_CA")))
            return "\(number) \(match.2)"
        }
        return shares == 1 ? "1 \(shareUnit)" : "\(shares) × \(shareUnit)"
    }
}

// MARK: - F4 Palier débloqué

/// Moment « Palier débloqué ! » : sceau qui rebondit, prix qui baisse en chiffres animés, haptique de succès.
/// Version locale en attendant `TierUnlockedCelebration` (T-033) dans `Core/Design/Components/`.
private struct TierCelebrationView: View {
    let celebration: OfferDetailViewModel.TierCelebration
    let tiers: [PriceTier]
    let totalShares: Int
    let shareUnit: String
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var badgeSize: CGFloat = 132
    @ScaledMetric(relativeTo: .largeTitle) private var sealSize: CGFloat = 60
    @State private var displayedPriceCents: Cents?
    @State private var bounce = 0
    @State private var didAppear = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                seal
                    .padding(.top, 40)

                VStack(spacing: 8) {
                    Text("Palier débloqué !")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.texte)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.texteSecondaire)
                        .multilineTextAlignment(.center)
                }

                priceCard
                shareCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(
            LinearGradient(colors: [Color.grenier.opacity(0.16), Color.fond], startPoint: .top, endPoint: .center)
                .background(Color.fond)
                .ignoresSafeArea()
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: onDone) {
                Text("Voir ma part")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(Color.grenier)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .presentationDetents([.large])
        .sensoryFeedback(.success, trigger: didAppear)
        .onAppear(perform: start)
    }

    private var seal: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: sealSize, weight: .semibold))
            .foregroundStyle(Color.onAccent)
            .symbolEffect(.bounce, value: bounce)
            .frame(width: badgeSize, height: badgeSize)
            .background(Color.grenier, in: .circle)
            .shadow(color: Color.grenier.opacity(0.3), radius: 16, y: 8)
            .accessibilityHidden(true)
    }

    private var subtitle: String {
        if celebration.isLastTier {
            return "Ta part fait tomber le dernier palier. Le meilleur prix vaut pour tout le groupe."
        }
        return "Ta part fait passer le groupe au palier \(celebration.tierNumber) sur \(celebration.tierCount). Le prix baisse pour tout le monde."
    }

    private var priceCard: some View {
        let price = displayedPriceCents ?? celebration.previousPriceCents
        return VStack(spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) { priceChange(price) }
                VStack(spacing: 4) { priceChange(price) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Le prix passe de \(Money.format(celebration.previousPriceCents)) à \(Money.format(celebration.newPriceCents)) le \(shareUnit)")

            TierProgressBar(tiers: tiers, committedShares: celebration.committedShares, totalShares: totalShares)
        }
        .grenierCard(padding: 20)
    }

    @ViewBuilder
    private func priceChange(_ price: Cents) -> some View {
        Text(Money.format(celebration.previousPriceCents))
            .priceStyle(.title3.bold())
            .strikethrough()
            .foregroundStyle(.texteSecondaire)
        Image(systemName: "chevron.right")
            .font(.headline)
            .foregroundStyle(.texteSecondaire)
        Text(Money.format(price))
            .priceStyle(.largeTitle.bold())
            .foregroundStyle(Color.grenier)
            .contentTransition(.numericText(value: Double(price)))
    }

    private var shareCard: some View {
        VStack(spacing: 0) {
            row(title: "Ta part") {
                Text("\(OfferDetailContent.quantityLabel(celebration.myQuantity, shareUnit: shareUnit)) · \(Money.format(celebration.myTotalCents))")
                    .font(.headline)
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(.texte)
            }
            if celebration.mySavingsCents > 0 {
                Divider().overlay(Color.piste)
                row(title: "Tu économises") {
                    SavingsBadge(kind: .amount(celebration.mySavingsCents))
                }
            }
        }
        .grenierCard(padding: 0)
    }

    private func row(title: String, @ViewBuilder trailing: () -> some View) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center))
        return layout {
            Text(title)
                .font(.body)
                .foregroundStyle(.texte)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }

    private func start() {
        guard !didAppear else { return }
        didAppear = true
        AccessibilityNotification.Announcement(
            "Palier débloqué ! Le prix passe de \(Money.format(celebration.previousPriceCents)) à \(Money.format(celebration.newPriceCents)) le \(shareUnit)."
        ).post()
        if reduceMotion {
            displayedPriceCents = celebration.newPriceCents
            return
        }
        displayedPriceCents = celebration.previousPriceCents
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            bounce += 1
            withAnimation(.smooth(duration: 0.8)) {
                displayedPriceCents = celebration.newPriceCents
            }
        }
    }
}

// MARK: - Previews

#Preview("Fiche clair") {
    NavigationStack {
        OfferDetailScreen(offerId: FakeData.ID.potatoOffer)
    }
    .environment(\.appContext, .instant)
}

#Preview("Fiche sombre") {
    NavigationStack {
        OfferDetailScreen(offerId: FakeData.ID.potatoOffer)
    }
    .environment(\.appContext, .instant)
    .preferredColorScheme(.dark)
}

#Preview("Palier clair") {
    TierCelebrationView(
        celebration: .init(tierNumber: 2, tierCount: 3, previousPriceCents: 1_150, newPriceCents: 990,
                           committedShares: 21, myQuantity: 2, myTotalCents: 1_980, mySavingsCents: 1_218),
        tiers: [PriceTier(minShares: 10, priceCents: 1_150), PriceTier(minShares: 20, priceCents: 990),
                PriceTier(minShares: 30, priceCents: 850)],
        totalShares: 40,
        shareUnit: "sac de 10 kg",
        onDone: {}
    )
}

#Preview("Palier sombre") {
    TierCelebrationView(
        celebration: .init(tierNumber: 3, tierCount: 3, previousPriceCents: 990, newPriceCents: 850,
                           committedShares: 31, myQuantity: 1, myTotalCents: 850, mySavingsCents: 749),
        tiers: [PriceTier(minShares: 10, priceCents: 1_150), PriceTier(minShares: 20, priceCents: 990),
                PriceTier(minShares: 30, priceCents: 850)],
        totalShares: 40,
        shareUnit: "sac de 10 kg",
        onDone: {}
    )
    .preferredColorScheme(.dark)
}
