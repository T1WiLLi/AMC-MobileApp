import SwiftUI

/// Ajouter un panier suspendu à sa part (E10, RQ-078) : 0, 2, 5 ou 10 $, ou un montant libre validé.
/// Le montant va au fonds du groupe et paie, anonymement, une partie de la part d'une famille du groupe.
///
///     SuspendedBasketPicker(amountCents: $suspendedCents, shareTotalCents: 2_600)
struct SuspendedBasketPicker: View {
    @Binding var amountCents: Cents
    /// Coût de la part (sans panier suspendu) ; s'il est fourni, le total à payer s'affiche.
    var shareTotalCents: Cents?

    @State private var isCustom: Bool
    @State private var customText: String
    @State private var errorMessage: String?
    @FocusState private var isFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var chipMinWidth: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var chipMinHeight: CGFloat = 44

    init(amountCents: Binding<Cents>, shareTotalCents: Cents? = nil) {
        _amountCents = amountCents
        self.shareTotalCents = shareTotalCents
        let current = amountCents.wrappedValue
        let isPreset = SolidarityMath.presetsCents.contains(current)
        _isCustom = State(initialValue: !isPreset)
        _customText = State(initialValue: isPreset ? "" : Self.editableText(current))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            chips
            if isCustom { customField }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.texte)
                    .symbolRenderingMode(.hierarchical)
                    .labelStyle(ErrorLabelStyle())
                    .transition(.opacity)
                    .accessibilityLabel("Erreur : \(errorMessage)")
            }
            if let shareTotalCents { summary(shareTotalCents) }
        }
        .grenierCard()
        .animation(reduceMotion ? nil : .smooth, value: isCustom)
        .animation(reduceMotion ? nil : .smooth, value: errorMessage)
        .sensoryFeedback(.selection, trigger: amountCents)
        .sensoryFeedback(.error, trigger: errorMessage) { _, new in new != nil }
    }

    // MARK: Parties

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: GrenierSymbol.solidarity)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.solidarite)
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? 0 : amountCents)
                .frame(width: iconSize, height: iconSize)
                .background(Color.solidarite.opacity(0.12), in: .rect(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Offrir un panier suspendu")
                    .font(.headline)
                    .foregroundStyle(Color.solidarite)
                Text("Ce montant paie une partie de la part d'une famille du groupe. Elle ne sait pas que c'est toi, et personne ne sait qui elle est.")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var chips: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: chipMinWidth), spacing: 8)], spacing: 8) {
            ForEach(SolidarityMath.presetsCents, id: \.self) { cents in
                chip(
                    title: cents == 0 ? String(localized: "Aucun") : Money.formatRounded(cents),
                    systemImage: cents == 0 ? "xmark" : nil,
                    accessibility: cents == 0 ? String(localized: "Aucun panier suspendu") : String(localized: "Ajouter \(Money.formatRounded(cents))"),
                    isSelected: !isCustom && amountCents == cents
                ) { selectPreset(cents) }
            }
            chip(title: String(localized: "Autre"), systemImage: "pencil", accessibility: String(localized: "Autre montant"), isSelected: isCustom) {
                isCustom = true
                validate(customText)
                isFieldFocused = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Montant du panier suspendu")
    }

    private func chip(title: String, systemImage: String? = nil, accessibility: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: isSelected ? "checkmark" : systemImage)
                        .imageScale(.small)
                        .contentTransition(.symbolEffect(.replace))
                } else if isSelected {
                    Image(systemName: "heart.fill")
                        .imageScale(.small)
                        .transition(.scale.combined(with: .opacity))
                }
                Text(title)
            }
            .font(.body.weight(.semibold))
            .fontDesign(.rounded)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: chipMinHeight)
            .padding(.horizontal, 8)
            .foregroundStyle(isSelected ? Color.onAccent : Color.solidarite)
            .background(isSelected ? Color.solidarite : Color.solidarite.opacity(0.12), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var customField: some View {
        HStack(spacing: 8) {
            TextField("Montant", text: $customText, prompt: Text("3,50"))
                .keyboardType(.decimalPad)
                .focused($isFieldFocused)
                .font(.title3.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(.texte)
                .onChange(of: customText) { _, text in validate(text) }
                .accessibilityLabel("Autre montant, en dollars")
                .accessibilityHint("Jusqu'à \(Money.formatRounded(SolidarityMath.maxSuspendedCents)).")
            Text("$")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.texteSecondaire)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: chipMinHeight)
        .background(Color.fond, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(errorMessage == nil ? Color.solidarite.opacity(0.4) : Color.grenier, lineWidth: 1.5)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func summary(_ shareTotal: Cents) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            row(String(localized: "Ta part"), symbol: "basket.fill", Money.format(shareTotal))
            row(String(localized: "Panier suspendu"), symbol: GrenierSymbol.solidarity, Money.format(amountCents), tint: .solidarite)
            row(String(localized: "Total à payer"), symbol: "creditcard.fill", Money.format(SolidarityMath.amountToPay(dueCents: shareTotal, subsidyCents: 0, suspendedCents: amountCents)), bold: true)
        }
    }

    private func row(_ label: String, symbol: String, _ value: String, tint: Color = .texte, bold: Bool = false) -> some View {
        let title = Label {
            Text(label).foregroundStyle(.texteSecondaire)
        } icon: {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint == .texte ? Color.grenier : tint)
        }
        return ViewThatFits(in: .horizontal) {
            HStack {
                title
                Spacer(minLength: 8)
                amount(value, tint: tint, bold: bold)
            }
            VStack(alignment: .leading, spacing: 2) {
                title
                amount(value, tint: tint, bold: bold)
            }
        }
        .font(bold ? .headline : .subheadline)
        .accessibilityElement(children: .combine)
    }

    private func amount(_ value: String, tint: Color, bold: Bool) -> some View {
        Text(value)
            .fontDesign(.rounded)
            .monospacedDigit()
            .fontWeight(bold ? .bold : .semibold)
            .foregroundStyle(tint)
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : .smooth, value: value)
    }

    // MARK: Logique

    private func selectPreset(_ cents: Cents) {
        isCustom = false
        isFieldFocused = false
        errorMessage = nil
        customText = ""
        amountCents = cents
    }

    private func validate(_ text: String) {
        switch SolidarityMath.parseAmount(text) {
        case .success(let cents):
            errorMessage = nil
            amountCents = cents
        case .failure(let error):
            errorMessage = error.message
        }
    }

    /// « 3,50 » pour pré-remplir le champ avec un montant libre déjà choisi.
    static func editableText(_ cents: Cents) -> String {
        let value = max(0, cents)
        return value % 100 == 0 ? "\(value / 100)" : String(format: "%d,%02d", value / 100, value % 100)
    }
}

/// Icône alignée sur la première ligne du message d'erreur, en Grenier pour attirer l'œil sans alarmer.
private struct ErrorLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.foregroundStyle(Color.grenier)
            configuration.title.fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
private struct SuspendedBasketPickerPreview: View {
    @State var amount: Cents = 500
    var body: some View {
        ScrollView {
            SuspendedBasketPicker(amountCents: $amount, shareTotalCents: 2_600)
                .padding()
        }
        .grenierBackground()
    }
}

#Preview("Clair") {
    SuspendedBasketPickerPreview()
}

#Preview("Sombre") {
    SuspendedBasketPickerPreview(amount: 1_250)
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    SuspendedBasketPickerPreview()
        .dynamicTypeSize(.accessibility5)
}
#endif
