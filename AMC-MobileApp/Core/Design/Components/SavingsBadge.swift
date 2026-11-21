import SwiftUI

/// Pilule d'économie (maquette SavingsBadge). Vert = argent économisé, jamais une action.
struct SavingsBadge: View {
    enum Kind: Equatable {
        /// Pilule pleine : « −37 % vs épicerie ».
        case percent(Int)
        /// Pilule légère : « 48 $ économisés ».
        case amount(Cents)
    }

    let kind: Kind
    /// Version courte pour les cartes : « −37 % ».
    var compact = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: compact ? 3 : 5) {
            Image(systemName: symbol)
                .imageScale(.small)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            Text(label)
                .contentTransition(.numericText())
        }
        .font(compact ? .caption.bold() : .subheadline.bold())
        .fontDesign(.rounded)
        .monospacedDigit()
        .padding(.horizontal, compact ? 8 : 12)
        .padding(.vertical, compact ? 4 : 6)
        .foregroundStyle(isFilled ? Color.onAccent : Color.economie)
        .background(isFilled ? Color.economie : Color.economie.opacity(0.12), in: .capsule)
        .fixedSize(horizontal: false, vertical: true) // AX5 : la pilule passe sur deux lignes, jamais « … ».
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// Flèche vers le bas pour un pourcentage, pièce pour un montant économisé.
    private var symbol: String {
        switch kind {
        case .percent: "arrow.down.circle.fill"
        case .amount: "dollarsign.circle.fill"
        }
    }

    private var isFilled: Bool {
        if case .percent = kind { !compact } else { false }
    }

    private var label: String {
        switch kind {
        case .percent(let value): compact ? "−\(value) %" : "−\(value) % vs épicerie"
        case .amount(let cents): "\(Money.formatRounded(cents)) économisés"
        }
    }

    /// « 37 pour cent moins cher qu'en épicerie », « 48 dollars économisés ».
    var accessibilityText: String {
        switch kind {
        case .percent(let value): "\(value) pour cent moins cher qu'en épicerie"
        case .amount(let cents): "\(Money.spoken(cents)) économisés"
        }
    }
}

#Preview("Clair") {
    VStack(spacing: 12) {
        HStack {
            SavingsBadge(kind: .percent(37))
            SavingsBadge(kind: .amount(4800))
        }
        SavingsBadge(kind: .percent(37), compact: true)
    }
    .padding()
}

#Preview("Sombre") {
    HStack {
        SavingsBadge(kind: .percent(37))
        SavingsBadge(kind: .amount(4800))
    }
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("AX5") {
    VStack(alignment: .leading, spacing: 12) {
        SavingsBadge(kind: .percent(37))
        SavingsBadge(kind: .amount(4_850))
        SavingsBadge(kind: .percent(37), compact: true)
    }
    .padding()
    .dynamicTypeSize(.accessibility5)
}
