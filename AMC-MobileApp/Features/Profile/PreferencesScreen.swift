import SwiftUI

/// RQ-017, RQ-018, RQ-019 : alimentation et allergies, langue, mode aîné. Chaque bascule s'enregistre aussitôt.
struct PreferencesScreen: View {
    @State private var viewModel: PreferencesViewModel

    init(viewModel: PreferencesViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        StateView(state: viewModel.state, retry: { await viewModel.load() }) { _ in
            PreferencesForm(viewModel: viewModel)
        }
        .navigationTitle("Préférences")
        .navigationBarTitleDisplayMode(.inline)
        .task { if viewModel.state.value == nil { await viewModel.load() } }
    }
}

/// Construit le ViewModel depuis l'environnement.
struct PreferencesLink: View {
    @Environment(\.appContext) private var context

    var body: some View {
        PreferencesScreen(viewModel: PreferencesViewModel(context: context))
    }
}

private struct PreferencesForm: View {
    let viewModel: PreferencesViewModel
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Form {
            if let error = viewModel.saveError {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Changement non enregistré").font(.headline)
                            Text(error.message).font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: error.systemImage).foregroundStyle(.red)
                    }
                }
                .grenierTransition(.banner)
            }

            ForEach(PreferencesViewModel.TagGroup.allCases) { group in
                Section {
                    ForEach(group.tags, id: \.self) { tag in
                        Toggle(isOn: Binding(
                            get: { viewModel.isSelected(tag) },
                            set: { _ in Task { await viewModel.toggle(tag) } }
                        )) {
                            Label(PreferencesViewModel.title(of: tag), systemImage: PreferencesViewModel.systemImage(of: tag))
                        }
                    }
                } header: {
                    Label(group.title, systemImage: group.systemImage)
                } footer: {
                    if group == .sourcing {
                        Text("Tes lots suggérés montrent d'abord ce qui te convient : \(viewModel.dietarySummary).")
                    }
                }
            }

            languageSection
        }
        .scrollContentBackground(.hidden)
        .grenierBackground()
        .grenierHaptic(.selection, trigger: viewModel.saveCount)
        .grenierHaptic(.error, trigger: viewModel.saveError)
        .grenierAnimation(.smooth, value: viewModel.saveError)
    }

    private var languageSection: some View {
        Section {
            // Ligne de réglage : libellé à gauche, choix (menu) à droite, icône alignée sur les autres lignes ;
            // empilée aux tailles d'accessibilité. (Un Picker seul plaçait le libellé au-dessus du choix.)
            Label {
                let isStacked = dynamicTypeSize.isAccessibilitySize
                let layout = isStacked
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    Text("Langue de l'app")
                        .layoutPriority(1)
                    if !isStacked { Spacer(minLength: 0) }
                    languagePicker
                }
            } icon: {
                Image(systemName: "globe")
            }
            Button("Ouvrir les Réglages de LeGrenier", systemImage: "gear") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        } header: {
            Label("Langue", systemImage: "character.bubble")
        } footer: {
            Text("L'app passe aussitôt à cette langue. Les messages de ton groupe et des producteurs te parviennent aussi dans cette langue.")
        }
    }

    /// T-171 : la langue s'applique tout de suite à toute l'app (voir AppLanguage).
    /// Menu avec le choix en texte qui passe à la ligne, à droite : le Picker `.menu` seul tronquait le libellé.
    private var languagePicker: some View {
        Menu {
            Picker("Langue de l'app", selection: Binding(
                get: { appLanguage },
                set: { language in
                    Task { await viewModel.setLanguage(AppUser.Language(rawValue: language.resolvedCode) ?? .french) }
                    AppLanguage.apply(language)
                }
            )) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(PreferencesViewModel.title(of: language)).tag(language)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(PreferencesViewModel.title(of: appLanguage))
                    .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel("Langue de l'app")
        .accessibilityValue(PreferencesViewModel.title(of: appLanguage))
    }
}

#Preview("Clair") {
    NavigationStack {
        PreferencesScreen(viewModel: PreferencesViewModel(context: .demo))
    }
}

#Preview("Sombre") {
    NavigationStack {
        PreferencesScreen(viewModel: PreferencesViewModel(context: .instant))
    }
    .preferredColorScheme(.dark)
}

#Preview("AX5") {
    NavigationStack {
        PreferencesScreen(viewModel: PreferencesViewModel(context: .instant))
    }
    .dynamicTypeSize(.accessibility5)
}

#Preview("Hors ligne") {
    NavigationStack {
        PreferencesScreen(viewModel: PreferencesViewModel(
            repositories: .fake(behavior: .failing()), userId: FakeData.ID.amina))
    }
}
