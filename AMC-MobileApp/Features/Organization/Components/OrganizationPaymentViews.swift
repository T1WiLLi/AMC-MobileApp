import SwiftUI

// T-207 : étape de paiement des organismes (don, paniers suspendus, parrainage) et reçus.
// Même carte que la réservation côté Famille (`PaymentCardView`), Face ID ou code, « Traitement… », puis reçu.

/// Une ligne « ce que ça couvre » sous la destination du paiement.
struct PaymentCoverageLine: Identifiable, Hashable {
    var systemImage: String
    var tint: Color
    var text: String
    var id: String { systemImage + text }
}

/// Étape de paiement puis reçu, dans une feuille. `onEdit` revient au choix du montant, `onDone` ferme la feuille.
struct OrganizationPaymentFlowView: View {
    let checkout: OrganizationCheckoutModel
    let coverage: [PaymentCoverageLine]
    let onEdit: () -> Void
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let receipt = checkout.receipt {
                OrganizationPaymentSuccessView(receipt: receipt, onDone: onDone)
                    .grenierTransition(.celebration)
            } else {
                OrganizationPaymentStep(checkout: checkout, coverage: coverage, onEdit: onEdit)
                    .grenierTransition(.banner)
            }
        }
        .grenierAnimation(.smooth, value: checkout.phase)
        .grenierHaptic(.success, trigger: checkout.receipt != nil) { _, new in new }
        .grenierHaptic(.error, trigger: checkout.phase) { _, new in
            if case .declined = new { return true }
            if case .failed = new { return true }
            return false
        }
        .interactiveDismissDisabled(checkout.isBusy)
    }
}

/// Récapitulatif du paiement : carte, montant, destination, ce que ça couvre, puis « Payer ».
struct OrganizationPaymentStep: View {
    let checkout: OrganizationCheckoutModel
    let coverage: [PaymentCoverageLine]
    let onEdit: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 24

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PaymentCardView(methodLabel: PaymentSimulator.methodLabel, status: cardStatus)

                amountBlock

                VStack(alignment: .leading, spacing: 12) {
                    Label("Destination", systemImage: "arrow.down.heart.fill")
                        .font(.headline)
                        .foregroundStyle(Color.texte)
                        .symbolRenderingMode(.hierarchical)
                    line(String(localized: "Fonds de solidarité de \(checkout.groupName)"),
                         systemImage: "heart.circle.fill", tint: .solidarite)
                    ForEach(coverage) { item in
                        line(item.text, systemImage: item.systemImage, tint: item.tint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .grenierCard()

                statusBanner

                VStack(alignment: .leading, spacing: 12) {
                    if checkout.isRecurring {
                        line(String(localized: "Prélevé chaque mois sur la carte de l'organisme, tant que le parrainage dure. Tu peux changer l'objectif ou y mettre fin quand tu veux."),
                             systemImage: "arrow.triangle.2.circlepath.circle.fill", tint: .grenier)
                    }
                    line(securityText, systemImage: "lock.shield.fill", tint: .grenier)
                    line(String(localized: "Anonyme : le groupe voit le total du fonds, jamais qui est aidé."),
                         systemImage: "eye.slash.fill", tint: .grenier)
                }
                .grenierCard()

                if dynamicTypeSize.isAccessibilitySize { payButton }
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollEdgeEffectStyle(.hard, for: .bottom)
        .safeAreaBar(edge: .bottom, spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize { payButton.padding(.horizontal, 16).padding(.vertical, 8) }
        }
    }

    private var cardStatus: PaymentCardView.Status {
        switch checkout.phase {
        case .review, .authenticating, .failed: .ready
        case .processing: .processing
        case .succeeded: .approved
        case .declined: .declined
        }
    }

    private var amountBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(checkout.isRecurring ? String(localized: "Prélevé chaque mois") : String(localized: "Montant du don"))
                .font(.subheadline)
                .foregroundStyle(Color.texteSecondaire)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Money.format(checkout.amountCents))
                    .priceStyle(.largeTitle.bold())
                    .foregroundStyle(Color.texte)
                    .contentTransition(.numericText(value: Double(checkout.amountCents)))
                if checkout.isRecurring {
                    Text("/ mois")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.texteSecondaire)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch checkout.phase {
        case .declined(let decline):
            banner(title: String(localized: "Paiement refusé"), message: decline.message,
                   systemImage: "xmark.octagon.fill", showsEdit: true)
        case .failed(let error):
            banner(title: String(localized: "Paiement non enregistré"),
                   message: String(localized: "\(error.message) Rien n'a été débité."),
                   systemImage: error.systemImage, showsEdit: false)
        default:
            EmptyView()
        }
    }

    private func banner(title: String, message: String, systemImage: String, showsEdit: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Color.solidarite)
                .symbolRenderingMode(.hierarchical)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.texte)
                .fixedSize(horizontal: false, vertical: true)
            if showsEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Modifier le montant", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
        .accessibilityElement(children: .contain)
    }

    private var securityText: String {
        switch checkout.biometry {
        case .faceID, .touchID, .opticID:
            String(localized: "Confirmé par \(checkout.biometry.title) : personne d'autre ne peut payer avec la carte de l'organisme.")
        case .passcodeOnly:
            String(localized: "Confirmé par le code de l'appareil : personne d'autre ne peut payer avec la carte de l'organisme.")
        case .unavailable:
            String(localized: "Paiement chiffré, confirmé par ce bouton.")
        }
    }

    private var payButton: some View {
        Button {
            Task { await checkout.pay() }
        } label: {
            HStack(spacing: 8) {
                if checkout.isBusy {
                    ProgressView()
                        .tint(Color.onAccent)
                } else {
                    Image(systemName: buttonSymbol)
                }
                Text(buttonTitle)
                    .contentTransition(.interpolate)
            }
            .font(.headline)
            .foregroundStyle(Color.onAccent)
            .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(Color.grenier)
        .disabled(checkout.isBusy)
        .accessibilityHint(checkout.biometry.canAuthenticate
                           ? String(localized: "Demande \(checkout.biometry.title).")
                           : "")
    }

    private var buttonSymbol: String {
        switch checkout.phase {
        case .declined, .failed: "arrow.clockwise"
        default: checkout.biometry.canAuthenticate ? checkout.biometry.systemImage : "creditcard.fill"
        }
    }

    private var buttonTitle: String {
        let amount = Money.format(checkout.amountCents)
        switch checkout.phase {
        case .authenticating: return String(localized: "Confirmation…")
        case .processing: return String(localized: "Traitement…")
        case .declined, .failed: return String(localized: "Réessayer")
        default:
            return checkout.isRecurring
                ? String(localized: "Payer \(amount) par mois")
                : String(localized: "Payer \(amount)")
        }
    }

    private func line(_ text: String, systemImage: String, tint: Color) -> some View {
        Label {
            Text(text)
                .foregroundStyle(Color.texte)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: iconWidth)
        }
        .font(.subheadline)
    }
}

/// Paiement accepté : remerciement animé, puis le reçu.
struct OrganizationPaymentSuccessView: View {
    let receipt: OrganizationPaymentReceipt
    let onDone: () -> Void
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GrenierSymbolScene(
                    symbol: "checkmark.seal.fill",
                    tint: .economie,
                    satellites: [.init("basket.fill"), .init("heart.fill", tint: .solidarite), .init("house.fill", tint: .economie)],
                    trigger: appeared
                )
                VStack(spacing: 8) {
                    Text(receipt.headline)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.texte)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(receipt.thanksMessage)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.texteSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
                OrganizationReceiptCard(receipt: receipt)
                VStack(spacing: 10) {
                    ShareLink(item: receipt.plainText()) {
                        Label("Partager le reçu", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glass)
                    Button(action: onDone) {
                        Label("Terminé", systemImage: "checkmark")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.grenier)
                }
            }
            .padding(24)
        }
        .onAppear { appeared = true }
        .accessibilityElement(children: .contain)
    }
}

/// Détail d'un reçu d'organisme : numéro, date, montant, moyen de paiement, destination et ce que ça couvre.
struct OrganizationReceiptCard: View {
    let receipt: OrganizationPaymentReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Reçu", systemImage: "doc.text.fill")
                    .font(.headline)
                    .foregroundStyle(Color.texte)
                    .symbolRenderingMode(.hierarchical)
                Spacer(minLength: 8)
                Text(Money.format(receipt.amountCents))
                    .priceStyle(.title3.bold())
                    .foregroundStyle(Color.texte)
            }
            Divider()
            ForEach(receipt.rows) { row in
                LabeledContent {
                    Text(row.value)
                        .foregroundStyle(Color.texte)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                } label: {
                    Label {
                        Text(row.title).foregroundStyle(Color.texteSecondaire)
                    } icon: {
                        Image(systemName: row.systemImage)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.grenier)
                    }
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
    }
}

/// Une ligne de l'historique des dons (Tableau) : quoi, pour qui, quand, combien ; touche pour le reçu.
struct DonationHistoryRow: View {
    let donation: OrganizationDonation

    private var isBaskets: Bool { donation.kind == .suspendedBaskets }
    private var tint: Color { isBaskets ? .grenier : .solidarite }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isBaskets ? "basket.fill" : "heart.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(isBaskets
                     ? String(localized: "\(FrenchPlural.count(donation.basketCount, "panier suspendu", plural: "paniers suspendus")) · \(donation.groupName)")
                     : String(localized: "Don au fonds · \(donation.groupName)"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.texte)
                    .fixedSize(horizontal: false, vertical: true)
                Text(donation.date.formatted(.dateTime.day().month(.wide).year().locale(AppLanguage.formattingLocale)))
                    .font(.caption)
                    .foregroundStyle(Color.texteSecondaire)
            }
            Spacer(minLength: 8)
            Text(Money.formatRounded(donation.amountCents))
                .priceStyle(.headline)
                .foregroundStyle(Color.texte)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.texteSecondaire)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .grenierCard()
        .accessibilityElement(children: .combine)
    }
}

/// Reçu d'un don de l'historique (Tableau, Impact), en feuille.
struct OrganizationReceiptSheet: View {
    let receipt: OrganizationPaymentReceipt
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.largeTitle)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.economie)
                            .accessibilityHidden(true)
                        Text(receipt.headline)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.texte)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                    OrganizationReceiptCard(receipt: receipt)
                }
                .padding(16)
            }
            .grenierBackground()
            .navigationTitle("Reçu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: receipt.plainText()) {
                        Label("Partager le reçu", systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Textes du reçu (Money est isolé au MainActor)

extension OrganizationPaymentReceipt {
    struct Row: Identifiable, Hashable {
        var title: String
        var systemImage: String
        var value: String
        var id: String { title }
    }

    @MainActor
    var formattedDate: String {
        date.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(AppLanguage.formattingLocale))
    }

    @MainActor
    var formattedAmount: String {
        isRecurring
            ? String(localized: "\(Money.format(amountCents)) par mois")
            : Money.format(amountCents)
    }

    /// « Fonds de solidarité de Parc-Ex ».
    var destination: String { String(localized: "Fonds de solidarité de \(groupName)") }

    /// Ce que le paiement couvre : paniers, familles.
    var coverageText: String {
        switch purpose {
        case .donation(let kind, let baskets, let households):
            let basketText = baskets > 0
                ? (kind == .suspendedBaskets
                   ? FrenchPlural.count(baskets, "panier suspendu", plural: "paniers suspendus")
                   : FrenchPlural.count(baskets, "panier entier", plural: "paniers entiers"))
                : String(localized: "Une partie d'un panier")
            guard households > 0 else { return basketText }
            return "\(basketText) · \(FrenchPlural.count(households, "famille couverte", plural: "familles couvertes"))"
        case .sponsorship(let goal):
            return String(localized: "\(FrenchPlural.count(goal, "panier suspendu", plural: "paniers suspendus")) par mois")
        }
    }

    @MainActor
    var headline: String {
        switch purpose {
        case .donation(let kind, let baskets, _):
            return kind == .suspendedBaskets
                ? String(localized: "\(FrenchPlural.count(baskets, "panier suspendu", plural: "paniers suspendus")) pour \(groupName)")
                : String(localized: "\(Money.formatRounded(amountCents)) dans le fonds de \(groupName)")
        case .sponsorship:
            return String(localized: "Tu parraines \(groupName)")
        }
    }

    var thanksMessage: String {
        switch purpose {
        case .donation(_, _, let households):
            return households > 0
                ? String(localized: "\(FrenchPlural.count(households, "famille")) recevront leur panier à la prochaine commande, sans que personne sache qui.")
                : String(localized: "Le fonds est prêt pour les prochaines familles qui en auront besoin.")
        case .sponsorship:
            return String(localized: "Le montant est prélevé chaque mois et versé au fonds du groupe. Les familles aidées restent anonymes.")
        }
    }

    @MainActor
    var rows: [Row] {
        [
            Row(title: String(localized: "Numéro"), systemImage: "number", value: number),
            Row(title: String(localized: "Date"), systemImage: "calendar", value: formattedDate),
            Row(title: isRecurring ? String(localized: "Montant mensuel") : String(localized: "Montant"),
                systemImage: "dollarsign.circle.fill", value: formattedAmount),
            Row(title: String(localized: "Moyen de paiement"), systemImage: "creditcard.fill", value: methodLabel),
            Row(title: String(localized: "Destination"), systemImage: "heart.circle.fill", value: destination),
            Row(title: String(localized: "Couvre"), systemImage: "basket.fill", value: coverageText),
        ]
    }

    /// Reçu en texte, à partager.
    @MainActor
    func plainText() -> String {
        var lines = [isRecurring ? String(localized: "Reçu d'engagement LeGrenier") : String(localized: "Reçu de don LeGrenier")]
        lines += rows.map { "\($0.title) : \($0.value)" }
        lines.append(String(localized: "Merci de soutenir ton quartier !"))
        return lines.joined(separator: "\n")
    }
}

extension OrganizationPaymentDecline {
    @MainActor
    var message: String {
        switch self {
        case .overCardLimit(let limit):
            String(localized: "Le montant dépasse le plafond de la carte de l'organisme (\(Money.formatRounded(limit))). Choisis un montant plus petit, ou fais plusieurs dons. Rien n'a été débité.")
        case .refusedByIssuer:
            String(localized: "La banque de l'organisme a refusé le paiement. Rien n'a été débité : réessaie dans un instant.")
        }
    }
}

// MARK: - Aperçus

#Preview("Paiement") {
    let portal = OrganizationPortalModel(repository: FakeOrganizationRepository(), organizationId: FakeData.ID.laRuche)
    let checkout = OrganizationCheckoutModel(
        portal: portal, purpose: .donation(.suspendedBaskets(count: 5), groupId: FakeData.ID.parcEx),
        amountCents: 7_500, groupName: "Parc-Extension", authenticator: FakeBiometricAuthenticator()
    )
    NavigationStack {
        OrganizationPaymentFlowView(
            checkout: checkout,
            coverage: [.init(systemImage: "basket.fill", tint: .grenier, text: "5 paniers entiers dans le fonds")],
            onEdit: {}, onDone: {}
        )
        .grenierBackground()
    }
    .task { await portal.load() }
}

#Preview("Reçu · sombre") {
    OrganizationReceiptSheet(receipt: OrganizationPaymentReceipt(
        number: "LG-20261122-4F9K2A", date: .now, amountCents: 7_500,
        methodLabel: PaymentSimulator.organizationCardLabel, groupName: "Parc-Extension",
        purpose: .donation(kind: .suspendedBaskets, basketCount: 5, householdsReached: 3)
    ))
    .preferredColorScheme(.dark)
}
