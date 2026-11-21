import SwiftUI

/// Bandeau discret, visible du seul ménage aidé (E10, RQ-082) : une partie de sa part a été offerte par ses voisins.
/// N'affiche rien si `subsidyCents` vaut 0. Ne dit jamais qui a donné.
///
///     SupportedHouseholdBanner(subsidyCents: share.subsidyCents)
struct SupportedHouseholdBanner: View {
    let subsidyCents: Cents

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 36
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(subsidyCents: Cents) {
        self.subsidyCents = subsidyCents
    }

    var body: some View {
        if subsidyCents > 0 {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: GrenierSymbol.solidarity)
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.solidarite)
                    .frame(width: iconSize, height: iconSize)
                    .background(Color.surface, in: .circle)
                    .symbolEffect(.bounce, value: appeared && !reduceMotion)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Une partie de ta part a été offerte par tes voisins")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.texte)
                    Label {
                        Text(detailText)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.economie)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Color.solidarite.opacity(0.12), in: .rect(cornerRadius: 24))
            .accessibilityElement(children: .combine)
            .onAppear { appeared = true }
        }
    }

    /// « 8,00 $ de moins à payer. Rien à faire de ton côté. »
    var detailText: String {
        String(localized: "\(Money.format(subsidyCents)) de moins à payer. Rien à faire de ton côté.")
    }
}

#if DEBUG
#Preview("Clair") {
    VStack(spacing: 12) {
        SupportedHouseholdBanner(subsidyCents: 800)
        SupportedHouseholdBanner(subsidyCents: 0)
    }
    .padding()
    .frame(maxHeight: .infinity, alignment: .top)
    .grenierBackground()
}

#Preview("Sombre") {
    SupportedHouseholdBanner(subsidyCents: 1_250)
        .padding()
        .frame(maxHeight: .infinity, alignment: .top)
        .grenierBackground()
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    ScrollView {
        SupportedHouseholdBanner(subsidyCents: 800)
            .padding()
    }
    .grenierBackground()
    .dynamicTypeSize(.accessibility5)
}
#endif
