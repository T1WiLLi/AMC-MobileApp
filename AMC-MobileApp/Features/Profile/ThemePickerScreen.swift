import SwiftUI

/// B-035 : choix du thème de l'app (accent, fond, coins), poussé depuis le Profil.
/// Le choix s'applique tout de suite à toute l'app (trait `AppTheme`) et reste après relance.
struct ThemePickerScreen: View {
    @AppStorage(AppTheme.storageKey) private var selection: AppTheme = .grenier
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ThemePreviewCard(theme: selection)
                    .id(selection)
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(BlurReplaceTransition(configuration: .downUp)))

                Label("Choisis ton thème", systemImage: "swatchpalette.fill")
                    .font(.headline)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)

                VStack(spacing: 12) {
                    ForEach(AppTheme.allCases) { theme in
                        ThemeRow(theme: theme, isSelected: theme == selection) {
                            withAnimation(reduceMotion ? nil : .smooth) { selection = theme }
                        }
                    }
                }

                Label("Le thème change l'accent, le fond et les coins des cartes, en clair comme en sombre. Dans un groupe, sa marque passe devant.",
                      systemImage: "info.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.texteSecondaire)
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(16)
        }
        .grenierBackground()
        .navigationTitle("Thème")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - Aperçu

/// Maquette miniature d'un lot dans le thème choisi : la même chose que ce que l'app va montrer.
private struct ThemePreviewCard: View {
    let theme: AppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "carrot.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.accentColor)
                    .frame(width: 48, height: 48)
                    .background(theme.accentColor.opacity(0.14), in: .rect(cornerRadius: theme.cornerRadius / 2))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Carottes du Québec · 5 kg")
                        .font(.headline)
                        .foregroundStyle(.texte)
                    Label("Ferme Rive-Nord · ferme dans 2 j", systemImage: "checkmark.seal.fill")
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                        .symbolRenderingMode(.hierarchical)
                }
                Spacer(minLength: 0)
            }
            ProgressView(value: 0.7) {
                Label("Palier 2 sur 3 · 14 familles", systemImage: "person.3.fill")
                    .font(.subheadline)
                    .foregroundStyle(.texte)
            }
            .tint(theme.accentColor)
            HStack {
                Text("2,60 $/kg").priceStyle(.title3.bold())
                    .foregroundStyle(.texte)
                Spacer()
                Label("Rejoindre", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Color.onAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(theme.accentColor, in: .capsule)
            }
        }
        .padding(16)
        .background(Color.surface, in: .rect(cornerRadius: theme.cornerRadius))
        .padding(12)
        .background(theme.fondColor, in: .rect(cornerRadius: theme.cornerRadius + 12))
        .overlay {
            RoundedRectangle(cornerRadius: theme.cornerRadius + 12)
                .strokeBorder(theme.accentColor.opacity(0.25), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aperçu du thème \(theme.title) : un lot avec son palier et le bouton Rejoindre.")
    }
}

// MARK: - Ligne

private struct ThemeRow: View {
    let theme: AppTheme
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 14) {
                Image(systemName: theme.symbol)
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.accentColor)
                    .frame(width: 44, height: 44)
                    .background(theme.accentColor.opacity(0.14), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.title)
                        .font(.headline)
                        .foregroundStyle(.texte)
                    Text(theme.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                }
                Spacer(minLength: 8)
                HStack(spacing: -6) {
                    Circle().fill(Color(theme.accentLight))
                    Circle().fill(Color(theme.accentDark))
                }
                .frame(height: 18)
                .frame(maxWidth: 32)
                .accessibilityHidden(true)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? theme.accentColor : Color.texteSecondaire)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(14)
            .background(Color.surface, in: .rect(cornerRadius: theme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .strokeBorder(isSelected ? theme.accentColor : .clear, lineWidth: 2)
            }
            .contentShape(.rect(cornerRadius: theme.cornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.title), \(theme.subtitle)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("Clair") {
    NavigationStack { ThemePickerScreen() }
}

#Preview("Sombre") {
    NavigationStack { ThemePickerScreen() }
        .preferredColorScheme(.dark)
}
