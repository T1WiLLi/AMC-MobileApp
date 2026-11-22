import SwiftUI

/// T-185 : champ d'adresse vérifié par Apple Maps.
/// Pendant la frappe (après 300 ms), les suggestions d'Apple s'affichent dessous ; on en touche une, ou on valide
/// au clavier (ou en quittant le champ), et l'adresse est vérifiée : coche verte et adresse normalisée réécrite,
/// ou « Adresse introuvable ». L'état vit dans `AddressFieldModel` (le view-model de l'écran le garde).
///
/// ```swift
/// AddressField("Adresse", text: $viewModel.address, model: viewModel.addressCheck,
///              prompt: "7420 rue Ogilvy, Montréal", isFocused: $addressFocused)
/// ```
struct AddressField: View {
    private let title: LocalizedStringKey
    @Binding private var text: String
    private let model: AddressFieldModel
    private let prompt: LocalizedStringKey?
    private let boxed: Bool
    private var isFocused: FocusState<Bool>.Binding

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter boxed: champ dans une boîte arrondie (cartes d'onboarding) plutôt qu'une ligne de `Form`.
    init(
        _ title: LocalizedStringKey,
        text: Binding<String>,
        model: AddressFieldModel,
        prompt: LocalizedStringKey? = nil,
        boxed: Bool = false,
        isFocused: FocusState<Bool>.Binding
    ) {
        self.title = title
        _text = text
        self.model = model
        self.prompt = prompt
        self.boxed = boxed
        self.isFocused = isFocused
    }

    private var status: AddressFieldModel.Status { model.status(for: text) }
    private var showsSuggestions: Bool {
        isFocused.wrappedValue && !model.suggestions.isEmpty && (status == .edited || status == .notFound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            field
            if showsSuggestions {
                suggestionList
                    .grenierTransition(.banner)
            }
            if status == .notFound {
                Label("Adresse introuvable. Vérifie le numéro et la rue.", systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .grenierTransition(.banner)
            }
            if status == .unverified {
                Label("Vérification impossible pour l'instant. L'adresse est gardée telle quelle.", systemImage: "wifi.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(Color.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                    .grenierTransition(.banner)
            }
        }
        .grenierAnimation(.smooth, value: model.suggestions)
        .grenierAnimation(.smooth, value: status)
        .grenierHaptic(.success, trigger: status == .valid) { _, new in new }
        .grenierHaptic(.warning, trigger: status == .notFound) { _, new in new }
        .task(id: text) {
            // Attente de 300 ms : on ne demande des suggestions qu'une fois la frappe posée.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, isFocused.wrappedValue else { return }
            await model.refreshSuggestions(for: text)
        }
        .onChange(of: text) { _, new in
            // Champ multiligne : « Retour » ajoute un saut de ligne au lieu d'appeler onSubmit. On le traite
            // comme une validation.
            guard new.contains("\n") else { return }
            text = new.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            isFocused.wrappedValue = false
        }
        .onChange(of: isFocused.wrappedValue) { _, focused in
            // On quitte le champ avec une adresse modifiée : on la vérifie tout de suite.
            if !focused, status == .edited { Task { await validate() } }
        }
    }

    private var field: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TextField(title, text: $text, prompt: prompt.map { Text($0) }, axis: .vertical)
                .lineLimit(1...3)
                .textContentType(.fullStreetAddress)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused(isFocused)
                .accessibilityValue(accessibilityStatus)
            statusIcon
        }
        .font(boxed ? .title3 : .body)
        .padding(boxed ? 12 : 0)
        .background {
            if boxed { RoundedRectangle(cornerRadius: 12).fill(AppTheme.fond) }
        }
    }

    @ViewBuilder private var statusIcon: some View {
        switch status {
        case .validating:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Vérification de l'adresse")
        case .valid:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.economie)
                .symbolEffect(.bounce, value: reduceMotion ? false : status == .valid)
                .accessibilityLabel("Adresse vérifiée")
        case .empty, .saved, .edited, .notFound, .unverified:
            // Introuvable ou non vérifiée : le message rouge sous le champ suffit (pas de deuxième icône).
            EmptyView()
        }
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.suggestions) { suggestion in
                Button {
                    Task { await pick(suggestion) }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.texte)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(Color.texteSecondaire)
                            }
                        }
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "mappin.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.grenier)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(suggestion.id)
                .accessibilityHint("Choisir cette adresse")
                if suggestion.id != model.suggestions.last?.id {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.piste.opacity(0.6), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggestions d'adresses")
    }

    private var accessibilityStatus: String {
        switch status {
        case .validating: String(localized: "Vérification de l'adresse")
        case .valid: String(localized: "Adresse vérifiée")
        case .notFound: String(localized: "Adresse introuvable. Vérifie le numéro et la rue.")
        case .unverified: String(localized: "Vérification impossible pour l'instant. L'adresse est gardée telle quelle.")
        case .empty, .saved, .edited: ""
        }
    }

    private func validate() async {
        if let normalized = await model.validate(text) { text = normalized }
    }

    private func pick(_ suggestion: AddressSuggestion) async {
        text = suggestion.id
        model.clearSuggestions()
        isFocused.wrappedValue = false
        if let normalized = await model.pick(suggestion) { text = normalized }
    }
}

private struct AddressFieldPreview: View {
    @State private var address = ""
    @State private var model = AddressFieldModel(validator: FakeAddressValidator(latency: .milliseconds(400)))
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section {
                AddressField("Adresse", text: $address, model: model, prompt: "7420 rue Ogilvy, Montréal", isFocused: $focused)
            } header: {
                Label("Lieu", systemImage: "mappin.and.ellipse")
            }
        }
        .scrollContentBackground(.hidden)
        .grenierBackground()
    }
}

#Preview("Adresse") { AddressFieldPreview() }

#Preview("Adresse (sombre, AX5)") {
    AddressFieldPreview()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
