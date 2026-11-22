import SwiftUI

/// E21-4 : part du ménage après la clôture, sur la fiche du lot.
/// « Payé Y $ · économisé Z $ grâce au groupe », « Paiement refusé » ou « Commande annulée · rien n'a été débité ».
struct SettlementCard: View {
    let settlement: ShareSettlement
    /// « 10 kg », « 2 × caisse ».
    let shareLabel: String
    /// Ouvre le reçu (part payée seulement).
    var onShowReceipt: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var badgeSize: CGFloat = 56
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: badgeSize * 0.5, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .frame(width: badgeSize, height: badgeSize)
                    .background(tint.opacity(0.14), in: .circle)
                    .symbolEffect(.bounce, value: reduceMotion ? false : appeared)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    title
                        .font(.headline)
                        .foregroundStyle(.texte)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            if let onShowReceipt, settlement.isPaid {
                Button(action: onShowReceipt) {
                    Label("Voir le reçu", systemImage: "doc.text.fill")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.glass)
                .tint(Color.grenier)
            }
        }
        .grenierCard()
        .onAppear { appeared = true }
    }

    @ViewBuilder
    private var title: some View {
        switch settlement {
        case .paid(let paid, let saved):
            if saved > 0 {
                Text("Payé \(Text(Money.format(paid)).bold()) · économisé \(Text(Money.format(saved)).foregroundStyle(Color.economie).bold()) grâce au groupe")
                    .contentTransition(.numericText(value: Double(paid)))
            } else {
                Text("Payé \(Text(Money.format(paid)).bold()) au pot du groupe")
            }
        case .declined:
            Text("Paiement refusé")
        case .cancelled:
            Text("Commande annulée · rien n'a été débité")
        }
    }

    private var message: String {
        switch settlement {
        case .paid:
            String(localized: "Prix final figé à la clôture pour \(shareLabel), payé au pot du groupe avec \(PaymentSimulator.methodLabel). Rendez-vous à la cueillette avec ton code QR.")
        case .declined(let due):
            String(localized: "Le paiement de \(Money.format(due)) pour \(shareLabel) n'est pas passé. Ta part reste réservée au prix final : la coordination du groupe te recontactera pour régler.")
        case .cancelled:
            String(localized: "Le minimum de parts n'a pas été atteint. Ta carte n'a pas été débitée et ta part est libérée.")
        }
    }

    private var symbol: String {
        switch settlement {
        case .paid: "checkmark.seal.fill"
        case .declined: "creditcard.trianglebadge.exclamationmark"
        case .cancelled: "xmark.circle.fill"
        }
    }

    private var tint: Color {
        switch settlement {
        case .paid: .economie
        case .declined: .red
        case .cancelled: .texteSecondaire
        }
    }
}

/// E21-4 : reçu de la part payée, en feuille : lot, quantité, prix unitaire au palier final,
/// subvention, don, total payé, moyen de paiement et numéro de commande.
struct ReceiptSheet: View {
    let receipt: Receipt

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.largeTitle)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.economie)
                            .accessibilityHidden(true)
                        Text("Total payé")
                            .font(.subheadline)
                            .foregroundStyle(.texteSecondaire)
                        Text(Money.format(receipt.totalCents))
                            .priceStyle(.largeTitle.bold())
                            .foregroundStyle(.texte)
                        if receipt.savingsCents > 0 {
                            SavingsBadge(kind: .amount(receipt.savingsCents), compact: true)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                }

                Section("Ta part") {
                    row("Lot", systemImage: "shippingbox.fill", value: receipt.productName)
                    row("Quantité", systemImage: "scalemass.fill",
                        value: "\(receipt.quantity) × \(receipt.shareUnit)")
                    row("Prix par part (palier final)", systemImage: "stairs",
                        value: Money.format(receipt.unitPriceCents))
                    row("Prix final", systemImage: "dollarsign.circle.fill",
                        value: Money.format(receipt.finalPriceCents))
                }

                Section("Paiement") {
                    if receipt.subsidyCents > 0 {
                        row("Fonds de solidarité", systemImage: "heart.circle.fill",
                            value: "−\(Money.format(receipt.subsidyCents))")
                    }
                    if receipt.donationCents > 0 {
                        row("Panier suspendu offert", systemImage: "basket.fill",
                            value: "+\(Money.format(receipt.donationCents))")
                    }
                    row("Total payé", systemImage: "creditcard.fill", value: Money.format(receipt.totalCents), bold: true)
                    row("Moyen de paiement", systemImage: "apple.logo",
                        value: receipt.payment?.methodLabel ?? PaymentSimulator.methodLabel)
                    if let date = receipt.payment?.date {
                        row("Date", systemImage: "calendar",
                            value: date.formatted(.dateTime.day().month(.wide).year().locale(AppLanguage.formattingLocale)))
                    }
                    row("Commande", systemImage: "number", value: receipt.groupOrderId)
                }

                Section {
                    Label("Paiement simulé pour la démo : aucun argent réel.", systemImage: "testtube.2")
                        .font(.footnote)
                        .foregroundStyle(.texteSecondaire)
                }
            }
            .scrollContentBackground(.hidden)
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
        .presentationDetents([.large])
    }

    private func row(_ title: LocalizedStringKey, systemImage: String, value: String, bold: Bool = false) -> some View {
        LabeledContent {
            Text(value)
                .font(bold ? .body.bold() : .body)
                .foregroundStyle(.texte)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        } label: {
            Label {
                Text(title).foregroundStyle(.texte)
            } icon: {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
            }
        }
    }
}

#Preview("Payé") {
    ScrollView {
        VStack(spacing: 16) {
            SettlementCard(settlement: .paid(paidCents: 2_480, savedCents: 1_080), shareLabel: "20 kg", onShowReceipt: {})
            SettlementCard(settlement: .declined(dueCents: 2_480), shareLabel: "20 kg")
            SettlementCard(settlement: .cancelled, shareLabel: "20 kg")
        }
        .padding()
    }
    .grenierBackground()
}

#Preview("Reçu") {
    ReceiptSheet(receipt: Receipt(
        householdId: "h", groupOrderId: "order-potatoes", productName: "Pommes de terre jaunes",
        shareUnit: "sac de 10 kg", quantity: 2, unitPriceCents: 990, finalPriceCents: 1_980,
        referencePriceCents: 3_198, savingsCents: 1_218, subsidyCents: 0, donationCents: 500,
        totalCents: 2_480, payment: nil
    ))
}
