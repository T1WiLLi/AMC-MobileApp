import SwiftUI

/// B-036 (T-152) : réglages de marque du groupe, pour le coordonnateur.
/// Présentée en feuille depuis la fiche du groupe (bouton « Marque du groupe » de la barre).
/// Aperçu en direct avec le thème réel, puis nom affiché, emblème, accent et message d'accueil.
struct GroupBrandingEditorScreen: View {
    @State var viewModel: GroupBrandingEditorViewModel
    /// Appelé avec le groupe à jour après l'enregistrement.
    var onSaved: (NeighborhoodGroup) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: Field?

    private enum Field { case name, welcome }

    private var theme: GroupTheme { viewModel.previewTheme }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    BrandingPreviewCard(theme: theme, fallbackName: viewModel.group.name)

                    nameSection
                    emblemSection
                    accentSection
                    welcomeSection

                    if !viewModel.isDefault {
                        Button {
                            withAnimation(reduceMotion ? nil : .smooth) { viewModel.resetToDefault() }
                        } label: {
                            Label("Revenir à la marque LeGrenier", systemImage: "arrow.uturn.backward.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .grenierTransition(.banner)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .grenierBackground()
            .tint(theme.accent)
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: theme)
            .navigationTitle("Marque du groupe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark", role: .cancel) { dismiss() }
                        .disabled(viewModel.status == .saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.status == .saving {
                        ProgressView()
                    } else {
                        Button("Enregistrer", systemImage: "checkmark") {
                            Task {
                                if let updated = await viewModel.save() {
                                    onSaved(updated)
                                    dismiss()
                                }
                            }
                        }
                        .disabled(!viewModel.canSave)
                    }
                }
            }
            .sensoryFeedback(.success, trigger: viewModel.savedCount)
            .alert(
                viewModel.error?.title ?? "",
                isPresented: Binding(
                    get: { viewModel.error != nil },
                    set: { if !$0 { viewModel.clearError() } }
                ),
                presenting: viewModel.error
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.message)
            }
        }
    }

    // MARK: Sections

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupsSectionHeader(title: "Nom affiché", systemImage: "textformat", tint: theme.accent)
            BrandingTextField(
                title: "Nom affiché",
                prompt: viewModel.group.name,
                systemImage: "character.cursor.ibeam",
                text: $viewModel.displayName,
                limit: GroupBrandingEditorViewModel.maxDisplayNameLength,
                error: viewModel.displayNameError,
                hint: "Vide : le nom du groupe, « \(viewModel.group.name) »."
            )
            .focused($focusedField, equals: .name)
            .submitLabel(.next)
            .onSubmit { focusedField = .welcome }
        }
    }

    private var emblemSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupsSectionHeader(title: "Emblème", systemImage: "seal.fill", tint: theme.accent)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 12)], spacing: 12) {
                ForEach(GroupBrandingEditorViewModel.emblems, id: \.self) { symbol in
                    let isSelected = (viewModel.emblem ?? GroupBranding.defaultEmblem) == symbol
                    Button {
                        viewModel.emblem = symbol == GroupBranding.defaultEmblem ? nil : symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(isSelected ? Color.onAccent : theme.accent)
                            .symbolEffect(.bounce, value: isSelected)
                            .frame(width: 56, height: 56)
                            .background(isSelected ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.fill.tertiary),
                                        in: .rect(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(symbol.replacingOccurrences(of: ".", with: " ")))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .grenierCard()
        }
    }

    private var accentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupsSectionHeader(title: "Couleur", systemImage: "paintpalette.fill", tint: theme.accent)
            VStack(spacing: 0) {
                AccentRow(name: String(localized: "LeGrenier (par défaut)"), light: nil, dark: nil,
                          isSelected: viewModel.accentId == nil) { viewModel.accentId = nil }
                ForEach(viewModel.availableAccents) { preset in
                    Divider().padding(.leading, 52)
                    AccentRow(name: preset.name, light: preset.light, dark: preset.dark,
                              isSelected: viewModel.accentId == preset.id) { viewModel.accentId = preset.id }
                }
            }
            .grenierCard(padding: 8)
            Label("Chaque couleur reste lisible en clair et en sombre (contraste AA).", systemImage: "checkmark.shield.fill")
                .font(.footnote)
                .foregroundStyle(.texteSecondaire)
        }
    }

    private var welcomeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupsSectionHeader(title: "Message d'accueil", systemImage: "text.bubble.fill", tint: theme.accent)
            BrandingTextField(
                title: "Message d'accueil",
                prompt: String(localized: "Bienvenue chez \(theme.displayName ?? viewModel.group.name)"),
                systemImage: "hand.wave.fill",
                text: $viewModel.welcomeMessage,
                limit: GroupBrandingEditorViewModel.maxWelcomeLength,
                error: viewModel.welcomeError,
                hint: "Affiché aux familles en tête de la fiche du groupe.",
                axis: .vertical
            )
            .focused($focusedField, equals: .welcome)
        }
    }
}

// MARK: - Composants

/// Aperçu de la marque, comme une famille la verra.
private struct BrandingPreviewCard: View {
    let theme: GroupTheme
    let fallbackName: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: theme.emblem)
                .font(.system(size: 40, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.onAccent)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 88, height: 88)
                .background(theme.accent.gradient, in: .circle)
                .shadow(color: theme.accent.opacity(0.35), radius: 16, y: 8)
            VStack(spacing: 4) {
                Text(theme.displayName ?? fallbackName)
                    .font(.title2.bold())
                    .foregroundStyle(.texte)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                if let welcome = theme.welcomeMessage {
                    Text(welcome)
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                        .multilineTextAlignment(.center)
                }
            }
            Label("Aperçu", systemImage: "eye.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(theme.accent.opacity(0.12), in: .capsule)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .grenierCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Aperçu de la marque : \(theme.displayName ?? fallbackName)"))
    }
}

private struct AccentRow: View {
    let name: String
    let light: String?
    let dark: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                swatch
                Text(name)
                    .foregroundStyle(.texte)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.texteSecondaire))
                    .symbolEffect(.bounce, value: isSelected)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Demi-pastille claire et sombre.
    @ViewBuilder private var swatch: some View {
        if let light = light.flatMap(BrandConfig.uiColor), let dark = dark.flatMap(BrandConfig.uiColor) {
            HStack(spacing: 0) {
                Color(uiColor: light)
                Color(uiColor: dark)
            }
            .frame(width: 32, height: 32)
            .clipShape(.circle)
            .accessibilityHidden(true)
        } else {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 32))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppTheme.accent)
                .accessibilityHidden(true)
        }
    }
}

private struct BrandingTextField: View {
    let title: LocalizedStringKey
    let prompt: String
    let systemImage: String
    @Binding var text: String
    let limit: Int
    let error: String?
    let hint: LocalizedStringKey
    var axis: Axis = .horizontal

    private var count: Int { text.trimmingCharacters(in: .whitespacesAndNewlines).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                TextField(title, text: $text, prompt: Text(prompt), axis: axis)
                    .lineLimit(axis == .vertical ? 2...4 : 1...1)
                    .textInputAutocapitalization(.sentences)
            } icon: {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
            }
            .grenierCard()
            .overlay {
                if error != nil {
                    RoundedRectangle(cornerRadius: 20).strokeBorder(.red, lineWidth: 1.5)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else {
                    Text(hint)
                        .foregroundStyle(.texteSecondaire)
                }
                Spacer()
                Text("\(count)/\(limit)")
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(count > limit ? AnyShapeStyle(Color.red) : AnyShapeStyle(Color.texteSecondaire))
            }
            .font(.footnote)
        }
    }
}

#Preview("Marque du groupe") {
    GroupBrandingEditorScreen(
        viewModel: GroupBrandingEditorViewModel(
            repositories: .fake(behavior: .instant),
            group: CardPreviewData.group,
            userId: CardPreviewData.group.coordinatorIds.first ?? "amina"
        )
    )
}

#Preview("Marque du groupe — sombre") {
    GroupBrandingEditorScreen(
        viewModel: GroupBrandingEditorViewModel(
            repositories: .fake(behavior: .instant),
            group: CardPreviewData.group,
            userId: CardPreviewData.group.coordinatorIds.first ?? "amina"
        )
    )
    .preferredColorScheme(.dark)
}
