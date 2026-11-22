import SwiftUI

/// Feuille « Financer » (T-116, RQ-081) : N paniers suspendus ou un don libre au fonds de solidarité d'un groupe.
/// Aperçu en direct (montant, paniers, familles couvertes), puis l'étape de paiement (T-207) et le reçu.
struct DonationSheet: View {
    enum Mode: String, CaseIterable, Identifiable {
        case baskets
        case fund

        var id: String { rawValue }
        var title: String {
            switch self {
            case .baskets: String(localized: "Paniers suspendus")
            case .fund: String(localized: "Don au fonds")
            }
        }
        var systemImage: String {
            switch self {
            case .baskets: "basket.fill"
            case .fund: "heart.circle.fill"
            }
        }
    }

    let model: OrganizationPortalModel
    let groupId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode: Mode = .baskets
    @State private var basketCount = 5
    @State private var amountCents: Cents = 5_000
    /// T-207 : étape de paiement ouverte après le choix du montant (nil : on choisit encore).
    @State private var checkout: OrganizationCheckoutModel?

    private var profile: GroupSolidarityProfile? { model.profile(id: groupId) }

    private var request: DonationRequest {
        switch mode {
        case .baskets: .suspendedBaskets(count: basketCount)
        case .fund: .fund(amountCents: amountCents)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let profile {
                    if let checkout {
                        OrganizationPaymentFlowView(
                            checkout: checkout,
                            coverage: coverage(for: checkout, profile: profile),
                            onEdit: backToForm,
                            onDone: { dismiss() }
                        )
                    } else {
                        form(profile)
                            .grenierTransition(.banner)
                    }
                } else {
                    EmptyStateView(title: "Groupe introuvable", systemImage: "questionmark.folder",
                                   message: "Ce groupe n'est plus disponible.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .grenierBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isDone {
                        Button(String(localized: "Terminé"), systemImage: "checkmark") { dismiss() }
                    } else if checkout != nil {
                        Button(String(localized: "Modifier le montant"), systemImage: "chevron.backward", action: backToForm)
                            .disabled(checkout?.isBusy == true)
                    } else {
                        Button(String(localized: "Annuler"), systemImage: "xmark") { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .grenierHaptic(.selection, trigger: mode)
        .onAppear { model.resetAction() }
    }

    private var isDone: Bool { checkout?.receipt != nil }

    private var title: String {
        if isDone { return String(localized: "Merci !") }
        return checkout == nil ? String(localized: "Financer") : String(localized: "Paiement")
    }

    private func backToForm() {
        guard checkout?.isBusy != true, !isDone else { return }
        model.resetAction()
        withGrenierAnimation(.smooth, reduceMotion: reduceMotion) { checkout = nil }
    }

    /// Ce que le paiement couvre, repris de l'aperçu « Ce que ça change ».
    private func coverage(for checkout: OrganizationCheckoutModel, profile: GroupSolidarityProfile) -> [PaymentCoverageLine] {
        guard case .donation(let request, _) = checkout.purpose,
              case .success(let plan) = model.plan(request, for: profile) else { return [] }
        return [
            PaymentCoverageLine(systemImage: "basket.fill", tint: .grenier, text: plan.basketSummary),
            PaymentCoverageLine(
                systemImage: "figure.2.and.child.holdinghands", tint: .solidarite,
                text: plan.householdsReached > 0
                    ? String(localized: "\(FrenchPlural.count(plan.householdsReached, "famille couverte", plural: "familles couvertes")) cette fois-ci")
                    : String(localized: "En réserve pour les prochaines familles aidées")
            ),
        ]
    }

    private func form(_ profile: GroupSolidarityProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(profile)

                Picker("Type de financement", selection: $mode.animation(.grenier(.snappy, reduceMotion: reduceMotion))) {
                    ForEach(Mode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .baskets: basketsInput(profile)
                case .fund: amountInput
                }

                preview(profile)
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Barre (et non simple inset) : le contenu s'estompe sous le bouton au lieu de passer dessous.
        .safeAreaBar(edge: .bottom, spacing: 0) { confirmBar(profile) }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }

    private func header(_ profile: GroupSolidarityProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(profile.groupName)
                    .font(.title2.bold())
                    .foregroundStyle(Color.texte)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                NeedBadge(level: profile.needLevel)
            }
            Label(MontrealNeighborhood.displayName(for: profile.neighborhood), systemImage: "mappin.and.ellipse")
                .font(.subheadline)
                .foregroundStyle(Color.texteSecondaire)
                .symbolRenderingMode(.hierarchical)
            CoverageBar(profile: profile)
        }
        .grenierCard()
    }

    private func basketsInput(_ profile: GroupSolidarityProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper(value: $basketCount, in: 1...OrganizationLedger.maxBasketsPerDonation) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(FrenchPlural.count(basketCount, "panier"))
                        .priceStyle(.title.bold())
                        .foregroundStyle(Color.texte)
                        .contentTransition(.numericText(value: Double(basketCount)))
                    Text("à \(Money.formatRounded(profile.basketPriceCents)) chacun")
                        .font(.subheadline)
                        .foregroundStyle(Color.texteSecondaire)
                }
            }
            .accessibilityValue(FrenchPlural.count(basketCount, "panier"))
            presetRow(OrganizationLedger.basketPresets, selected: basketCount, label: { "\($0)" }) { basketCount = $0 }
            if profile.basketsMissing > 0 {
                Button {
                    withGrenierAnimation(.snappy, reduceMotion: reduceMotion) {
                        basketCount = min(profile.basketsMissing, OrganizationLedger.maxBasketsPerDonation)
                    }
                } label: {
                    Label("Couvrir les \(FrenchPlural.count(profile.basketsMissing, "ménage")) en attente",
                          systemImage: "wand.and.sparkles")
                }
                .buttonStyle(.glass)
                .tint(.solidarite)
            }
        }
        .grenierAnimation(.snappy, value: basketCount)
        .grenierCard()
    }

    private var amountInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper(value: $amountCents, in: 500...OrganizationLedger.maxDonationCents, step: 500) {
                Text(Money.formatRounded(amountCents))
                    .priceStyle(.title.bold())
                    .foregroundStyle(Color.texte)
                    .contentTransition(.numericText(value: Double(amountCents)))
            }
            .accessibilityValue(Money.spoken(amountCents))
            presetRow(OrganizationLedger.amountPresetsCents, selected: amountCents,
                      label: { Money.formatRounded($0) }) { amountCents = $0 }
        }
        .grenierAnimation(.snappy, value: amountCents)
        .grenierCard()
    }

    private func presetRow<Value: Hashable>(
        _ values: [Value],
        selected: Value,
        label: @escaping (Value) -> String,
        select: @escaping (Value) -> Void
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { presetButtons(values, selected: selected, label: label, select: select) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                presetButtons(values, selected: selected, label: label, select: select)
            }
        }
    }

    private func presetButtons<Value: Hashable>(
        _ values: [Value],
        selected: Value,
        label: @escaping (Value) -> String,
        select: @escaping (Value) -> Void
    ) -> some View {
        ForEach(values, id: \.self) { value in
            let isSelected = value == selected
            Button {
                withGrenierAnimation(.snappy, reduceMotion: reduceMotion) { select(value) }
            } label: {
                Text(label(value))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.onAccent : Color.texte)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, 6)
                    .background(isSelected ? Color.grenier : Color.piste.opacity(0.6), in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    @ViewBuilder
    private func preview(_ profile: GroupSolidarityProfile) -> some View {
        switch model.plan(request, for: profile) {
        case .success(let plan):
            VStack(alignment: .leading, spacing: 10) {
                Label("Ce que ça change", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(Color.texte)
                    .symbolRenderingMode(.hierarchical)
                previewRow("basket.fill", tint: .grenier,
                           text: plan.basketSummary,
                           value: plan.basketCount)
                previewRow("figure.2.and.child.holdinghands", tint: .solidarite,
                           text: plan.householdsReached > 0
                               ? String(localized: "\(FrenchPlural.count(plan.householdsReached, "famille couverte", plural: "familles couvertes")) cette fois-ci")
                               : String(localized: "En réserve pour les prochaines familles aidées"),
                           value: plan.householdsReached)
                previewRow("cart.fill", tint: .economie,
                           text: String(localized: "≈ \(Money.formatRounded(OrganizationLedger.groceryValue(ofGroupSpend: plan.amountCents))) d'épicerie au prix du magasin"),
                           value: plan.amountCents)
                Text("Anonyme : le groupe voit le total du fonds, jamais qui est aidé.")
                    .font(.caption)
                    .foregroundStyle(Color.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .grenierCard()
        case .failure(let error):
            Label(error.message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(Color.solidarite)
                .grenierCard()
        }
        if let error = model.actionError {
            Label(error.message, systemImage: error.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.solidarite)
                .symbolRenderingMode(.hierarchical)
                .frame(maxWidth: .infinity, alignment: .leading)
                .grenierCard()
                .grenierTransition(.banner)
        }
    }

    private func previewRow(_ systemImage: String, tint: Color, text: String, value: Int) -> some View {
        Label {
            Text(text)
                .foregroundStyle(Color.texte)
                .contentTransition(.numericText(value: Double(value)))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
        .font(.subheadline)
    }

    private func confirmBar(_ profile: GroupSolidarityProfile) -> some View {
        let plan = try? OrganizationLedger.plan(request, for: profile)
        return Button {
            guard let plan else { return }
            model.resetAction()
            let next = OrganizationCheckoutModel(
                portal: model, purpose: .donation(request, groupId: groupId),
                amountCents: plan.amountCents, groupName: profile.groupName
            )
            withGrenierAnimation(.smooth, reduceMotion: reduceMotion) { checkout = next }
        } label: {
            HStack {
                Image(systemName: "creditcard.fill")
                Text(plan.map { String(localized: "Continuer · \(Money.formatRounded($0.amountCents))") } ?? String(localized: "Continuer"))
                    .contentTransition(.numericText())
            }
            .font(.headline)
            .foregroundStyle(Color.onAccent)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .tint(.grenier)
        .disabled(plan == nil)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview("Clair") {
    let model = OrganizationPortalModel(repository: FakeOrganizationRepository(), organizationId: FakeData.ID.laRuche)
    DonationSheet(model: model, groupId: FakeData.ID.parcEx)
        .task { await model.load() }
}

#Preview("Sombre") {
    let model = OrganizationPortalModel(repository: FakeOrganizationRepository(), organizationId: FakeData.ID.laRuche)
    DonationSheet(model: model, groupId: FakeData.ID.montrealNord)
        .task { await model.load() }
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    let model = OrganizationPortalModel(repository: FakeOrganizationRepository(), organizationId: FakeData.ID.laRuche)
    DonationSheet(model: model, groupId: FakeData.ID.parcEx)
        .task { await model.load() }
        .dynamicTypeSize(.accessibility5)
}
