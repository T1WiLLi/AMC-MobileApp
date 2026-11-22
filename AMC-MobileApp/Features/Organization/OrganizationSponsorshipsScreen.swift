import SwiftUI

/// Onglet Parrainages du portail Organismes (T-116, RQ-081) : groupes parrainés et leur objectif du mois,
/// puis les groupes à parrainer, du plus grand besoin au plus petit (les plus proches d'abord à besoin égal).
struct OrganizationSponsorshipsScreen: View {
    let model: OrganizationPortalModel?

    @State private var sponsorTarget: GroupSolidarityProfile?
    @State private var donationTarget: GroupSolidarityProfile?

    var body: some View {
        NavigationStack {
            OrganizationStateContainer(model: model) { model, _ in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        OrganizationSectionTitle("Tes parrainages", systemImage: "hands.and.sparkles.fill")
                        if model.sponsoredGroups.isEmpty {
                            Label("Parraine un groupe pour lui promettre des paniers chaque mois.",
                                  systemImage: "hand.raised.fill")
                                .font(.subheadline)
                                .foregroundStyle(Color.texteSecondaire)
                                .symbolRenderingMode(.hierarchical)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .grenierCard()
                        }
                        ForEach(Array(model.sponsoredGroups.enumerated()), id: \.element.id) { index, profile in
                            SponsoredGroupCard(
                                profile: profile,
                                sponsorship: model.sponsorship(ofGroup: profile.groupId),
                                basketsThisMonth: model.basketsThisMonth(groupId: profile.groupId),
                                onFund: { donationTarget = profile },
                                onEdit: { sponsorTarget = profile }
                            )
                            .grenierAppear(index: index)
                        }

                        OrganizationSectionTitle("Groupes à parrainer", systemImage: "map.fill", tint: .economie)
                        ForEach(Array(model.sponsorableGroups.enumerated()), id: \.element.id) { index, profile in
                            GroupNeedCard(profile: profile, distance: model.distanceText(for: profile)) {
                                Button {
                                    sponsorTarget = profile
                                } label: {
                                    Label("Parrainer ce groupe", systemImage: "hands.and.sparkles.fill")
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                }
                                .buttonStyle(.glass)
                                .tint(.grenier)
                            }
                            .contextMenu {
                                Button("Parrainer", systemImage: "hands.and.sparkles.fill") { sponsorTarget = profile }
                                Button("Financer des paniers", systemImage: "basket.fill") { donationTarget = profile }
                            }
                            .grenierAppear(index: model.sponsoredGroups.count + index)
                        }
                    }
                    .padding(16)
                }
                .refreshable { await model.load() }
                // T-208 : toucher un groupe ouvre sa fiche publique.
                .organizationGroupDestination(model: model)
                .sheet(item: $sponsorTarget) { profile in
                    SponsorSheet(model: model, groupId: profile.groupId)
                }
                .sheet(item: $donationTarget) { profile in
                    DonationSheet(model: model, groupId: profile.groupId)
                }
                .grenierHaptic(.success, trigger: model.sponsoredGroups.count)
            }
            .grenierBackground()
            .navigationTitle("Parrainages")
            .profileToolbar()
        }
    }
}

/// Carte d'un groupe parrainé : objectif du mois et progrès.
struct SponsoredGroupCard: View {
    let profile: GroupSolidarityProfile
    let sponsorship: Sponsorship?
    let basketsThisMonth: Int
    let onFund: () -> Void
    let onEdit: () -> Void

    private var goal: Int { max(1, sponsorship?.monthlyBasketGoal ?? 1) }
    private var progress: Double { min(1, Double(basketsThisMonth) / Double(goal)) }
    private var isReached: Bool { basketsThisMonth >= goal }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.groupName)
                        .font(.headline)
                        .foregroundStyle(Color.texte)
                    Label(MontrealNeighborhood.displayName(for: profile.neighborhood), systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(Color.texteSecondaire)
                        .symbolRenderingMode(.hierarchical)
                }
                Spacer(minLength: 8)
                NeedBadge(level: profile.needLevel)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(isReached ? String(localized: "Objectif du mois atteint") : String(localized: "Objectif du mois"),
                          systemImage: isReached ? "trophy.fill" : "target")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isReached ? Color.economie : Color.texte)
                        .contentTransition(.symbolEffect(.replace))
                    Spacer()
                    Text("\(basketsThisMonth) / \(goal)")
                        .priceStyle(.headline)
                        .foregroundStyle(Color.texte)
                        .contentTransition(.numericText(value: Double(basketsThisMonth)))
                }
                .font(.subheadline.weight(.semibold))
                ProgressView(value: progress)
                    .tint(isReached ? Color.economie : Color.grenier)
                    .accessibilityLabel("Objectif du mois")
                    .accessibilityValue("\(basketsThisMonth) paniers sur \(goal)")
                if let sponsorship {
                    Text("Parrain depuis le \(sponsorship.startedAt.formatted(.dateTime.day().month(.wide).year().locale(AppLanguage.formattingLocale)))")
                        .font(.caption)
                        .foregroundStyle(Color.texteSecondaire)
                }
            }
            .grenierAnimation(.smooth, value: basketsThisMonth)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttons }
                VStack(spacing: 8) { buttons }
            }
        }
        .grenierCard()
        .contextMenu {
            Button("Financer des paniers", systemImage: "basket.fill", action: onFund)
            Button("Modifier le parrainage", systemImage: "slider.horizontal.3", action: onEdit)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button(action: onFund) {
            Label("Financer", systemImage: "heart.fill")
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.glass)
        .tint(.grenier)
        Button(action: onEdit) {
            Label("Modifier", systemImage: "slider.horizontal.3")
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.glass)
    }
}

/// Feuille « Parrainer » : objectif mensuel de paniers, coût estimé, et fin du parrainage s'il existe.
struct SponsorSheet: View {
    let model: OrganizationPortalModel
    let groupId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var goal = 10
    @State private var confirmsEnd = false

    private var profile: GroupSolidarityProfile? { model.profile(id: groupId) }
    private var existing: Sponsorship? { model.sponsorship(ofGroup: groupId) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let profile {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(profile.groupName)
                                .font(.title2.bold())
                                .foregroundStyle(Color.texte)
                            Text("Parrainer, c'est promettre au groupe un nombre de paniers suspendus chaque mois. Ton organisme apparaît comme parrain, les familles aidées restent anonymes.")
                                .font(.subheadline)
                                .foregroundStyle(Color.texteSecondaire)
                                .fixedSize(horizontal: false, vertical: true)
                            CoverageBar(profile: profile)
                        }
                        .grenierCard()

                        VStack(alignment: .leading, spacing: 12) {
                            Stepper(value: $goal, in: 1...OrganizationLedger.maxBasketsPerDonation) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(FrenchPlural.count(goal, "panier")) par mois")
                                        .priceStyle(.title2.bold())
                                        .foregroundStyle(Color.texte)
                                        .contentTransition(.numericText(value: Double(goal)))
                                    Text("≈ \(Money.formatRounded(goal * profile.basketPriceCents)) par mois")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.texteSecondaire)
                                        .contentTransition(.numericText(value: Double(goal)))
                                }
                            }
                            HStack(spacing: 8) {
                                ForEach(OrganizationLedger.sponsorshipGoalPresets, id: \.self) { preset in
                                    Button("\(preset)") {
                                        withGrenierAnimation(.snappy, reduceMotion: reduceMotion) { goal = preset }
                                    }
                                    .buttonStyle(.glass)
                                    .tint(goal == preset ? .grenier : nil)
                                    .frame(maxWidth: .infinity)
                                    .accessibilityLabel("\(preset) paniers")
                                    .accessibilityAddTraits(goal == preset ? .isSelected : [])
                                }
                            }
                        }
                        .grenierCard()
                        .grenierHaptic(.selection, trigger: goal)

                        if let error = model.actionError {
                            Label(error.message, systemImage: error.systemImage)
                                .foregroundStyle(Color.solidarite)
                                .grenierCard()
                        }

                        if existing != nil {
                            Button(role: .destructive) {
                                confirmsEnd = true
                            } label: {
                                Label("Mettre fin au parrainage", systemImage: "xmark.circle")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    .padding(16)
                }
            }
            .grenierBackground()
            .navigationTitle(existing == nil ? String(localized: "Parrainer") : String(localized: "Mon parrainage"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                Button {
                    Task {
                        if await model.sponsor(groupId: groupId, monthlyBasketGoal: goal) { dismiss() }
                    }
                } label: {
                    HStack {
                        if model.isSubmitting { ProgressView().tint(Color.onAccent) }
                        Label(existing == nil ? String(localized: "Parrainer ce groupe") : String(localized: "Enregistrer l'objectif"),
                              systemImage: "hands.and.sparkles.fill")
                    }
                    .font(.headline)
                    .foregroundStyle(Color.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(.grenier)
                .disabled(model.isSubmitting || profile == nil)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .confirmationDialog("Mettre fin au parrainage ?", isPresented: $confirmsEnd, titleVisibility: .visible) {
                Button("Mettre fin", role: .destructive) {
                    Task { if await model.endSponsorship(groupId: groupId) { dismiss() } }
                }
            } message: {
                Text("Les paniers déjà financés restent dans le fonds du groupe.")
            }
        }
        // T-203 : en détente moyenne, la rangée 5/10/20/40 passait sous le bouton « Parrainer ce groupe ».
        .presentationDetents([.large])
        .onAppear {
            model.resetAction()
            if let existing { goal = existing.monthlyBasketGoal }
        }
    }
}

#Preview("Clair") {
    let model = OrganizationPortalModel(repository: FakeOrganizationRepository(), organizationId: FakeData.ID.laRuche)
    OrganizationSponsorshipsScreen(model: model)
        .task { await model.load() }
}

#Preview("Sombre") {
    let model = OrganizationPortalModel(repository: FakeOrganizationRepository(), organizationId: FakeData.ID.laRuche)
    OrganizationSponsorshipsScreen(model: model)
        .task { await model.load() }
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    let model = OrganizationPortalModel(repository: FakeOrganizationRepository(), organizationId: FakeData.ID.laRuche)
    OrganizationSponsorshipsScreen(model: model)
        .task { await model.load() }
        .dynamicTypeSize(.accessibility5)
}
