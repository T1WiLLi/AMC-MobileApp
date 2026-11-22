import SwiftUI

/// T-181 : « + Panier suspendu » en un geste, juste sous le choix de la part : 5, 10 ou 20 $.
/// Un tap choisit le montant, un tap sur la même puce le retire. Le montant est enregistré avec la part
/// et paie, sans nom, une partie de la part d'une famille du groupe (`SolidarityLedger`).
struct SuspendedBasketChips: View {
    @Binding var amountCents: Cents
    var choices: [Cents] = [500, 1_000, 2_000]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var chipHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(amountCents > 0 ? "Panier suspendu : \(Money.formatRounded(amountCents)) offerts" : "Offrir un panier suspendu")
                    .contentTransition(.numericText(value: Double(amountCents)))
            } icon: {
                Image(systemName: amountCents > 0 ? "heart.fill" : "heart")
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? 0 : amountCents)
                    .contentTransition(.symbolEffect(.replace))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.solidarite)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(choices, id: \.self) { cents in
                    chip(cents)
                }
            }
            Text("Une famille du groupe reçoit ce montant sur sa part, sans savoir de qui.")
                .font(.footnote)
                .foregroundStyle(.texteSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard(padding: 14)
        .animation(reduceMotion ? nil : .smooth, value: amountCents)
        .sensoryFeedback(.selection, trigger: amountCents)
    }

    private func chip(_ cents: Cents) -> some View {
        let isOn = amountCents == cents
        return Button {
            amountCents = isOn ? 0 : cents
        } label: {
            Label {
                Text(isOn ? Money.formatRounded(cents) : "+ \(Money.formatRounded(cents))")
            } icon: {
                if isOn { Image(systemName: "checkmark").imageScale(.small) }
            }
            .font(.body.weight(.semibold))
            .fontDesign(.rounded)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: chipHeight)
            .foregroundStyle(isOn ? Color.onAccent : Color.solidarite)
            .background(isOn ? Color.solidarite : Color.solidarite.opacity(0.12), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "Retirer le panier suspendu de \(Money.formatRounded(cents))" : "Ajouter un panier suspendu de \(Money.formatRounded(cents))")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#if DEBUG
private struct SuspendedBasketChipsPreview: View {
    @State var amount: Cents = 0
    var body: some View {
        SuspendedBasketChips(amountCents: $amount).padding().grenierBackground()
    }
}

#Preview("Clair") { SuspendedBasketChipsPreview() }
#Preview("AX5") { SuspendedBasketChipsPreview().dynamicTypeSize(.accessibility5) }
#endif
