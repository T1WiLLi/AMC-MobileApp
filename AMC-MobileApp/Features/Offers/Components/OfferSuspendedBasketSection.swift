import SwiftUI

/// Panier suspendu juste avant de valider sa part (E10, RQ-078) : rien, 5 $ en un geste ou 10 $.
/// Le montant s'ajoute au total de la barre du bas et s'enregistre sur la part à la validation
/// (`OfferDetailViewModel.reserve()`), puis un cœur remercie la famille.
///
///     OfferSuspendedBasketSection(viewModel: viewModel)
struct OfferSuspendedBasketSection: View {
    @Bindable var viewModel: OfferDetailViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var heartSize: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SuspendedBasketPicker(
                amountCents: $viewModel.suspendedBasketCents,
                title: "Ajouter un panier suspendu",
                presetsCents: OfferDetailViewModel.suspendedBasketPresetsCents,
                allowsCustomAmount: false
            )

            if let given = viewModel.state.value?.myDonationCents, given > 0 {
                thanks(given: given)
                    .grenierTransition(.banner)
            }
        }
        .grenierAnimation(.smooth, value: viewModel.donationCount)
        .sensoryFeedback(.success, trigger: viewModel.donationCount)
        .onChange(of: viewModel.donationCount) { _, _ in
            guard let cents = viewModel.lastDonationCents else { return }
            AccessibilityNotification.Announcement(
                String(localized: "Merci ! Ton panier suspendu de \(Money.format(cents)) est offert.")
            ).post()
        }
    }

    private func thanks(given: Cents) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.solidarite)
                .symbolEffect(.bounce.up.byLayer, options: .nonRepeating, value: reduceMotion ? 0 : viewModel.donationCount)
                .frame(width: heartSize, height: heartSize)
                .background(Color.solidarite.opacity(0.12), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.lastDonationCents == nil ? "Tu offres un panier suspendu" : "Merci, c'est offert !")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.solidarite)
                Text("\(Text(Money.format(given)).monospacedDigit().bold()) pour une famille du groupe, payés à la cueillette avec ta part.")
                    .font(.footnote)
                    .foregroundStyle(.texteSecondaire)
                    .contentTransition(.numericText(value: Double(given)))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Panier suspendu offert : \(Money.format(given)) pour une famille du groupe, payés à la cueillette avec ta part.")
    }
}

#if DEBUG
#Preview("Clair") {
    @Previewable @State var viewModel = OfferDetailViewModel(
        repositories: .fake(behavior: .instant), offerId: FakeData.ID.potatoOffer,
        householdId: FakeData.ID.aminaHousehold, groupId: FakeData.ID.saintMichel
    )
    ScrollView {
        OfferSuspendedBasketSection(viewModel: viewModel)
            .padding()
    }
    .grenierBackground()
    .task { await viewModel.load() }
}

#Preview("AX5 sombre") {
    @Previewable @State var viewModel = OfferDetailViewModel(
        repositories: .fake(behavior: .instant), offerId: FakeData.ID.potatoOffer,
        householdId: FakeData.ID.aminaHousehold, groupId: FakeData.ID.saintMichel
    )
    ScrollView {
        OfferSuspendedBasketSection(viewModel: viewModel)
            .padding()
    }
    .grenierBackground()
    .dynamicTypeSize(.accessibility5)
    .preferredColorScheme(.dark)
    .task { await viewModel.load() }
}
#endif
