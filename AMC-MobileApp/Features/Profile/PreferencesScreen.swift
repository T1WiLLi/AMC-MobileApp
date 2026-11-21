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
        .seniorModeTextSize()
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
    @AppStorage(SeniorMode.storageKey) private var seniorModeStorage = false
    @Environment(\.openURL) private var openURL

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
            seniorSection
        }
        .scrollContentBackground(.hidden)
        .grenierBackground()
        .grenierHaptic(.selection, trigger: viewModel.saveCount)
        .grenierHaptic(.error, trigger: viewModel.saveError)
        .grenierAnimation(.smooth, value: viewModel.saveError)
        .onChange(of: viewModel.user?.seniorMode, initial: true) { _, isOn in
            if let isOn { seniorModeStorage = isOn }
        }
    }

    private var languageSection: some View {
        Section {
            Picker(selection: Binding(
                get: { viewModel.user?.language ?? .french },
                set: { language in Task { await viewModel.setLanguage(language) } }
            )) {
                ForEach(AppUser.Language.allCases, id: \.self) { language in
                    Text(PreferencesViewModel.title(of: language)).tag(language)
                }
            } label: {
                Label("Langue de l'app", systemImage: "globe")
            }
            Button("Ouvrir les Réglages de LeGrenier", systemImage: "gear") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        } header: {
            Label("Langue", systemImage: "character.bubble")
        } footer: {
            Text("Les messages de ton groupe et des producteurs te parviennent dans cette langue.")
        }
    }

    private var seniorSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { viewModel.user?.seniorMode ?? false },
                set: { isOn in Task { await viewModel.setSeniorMode(isOn) } }
            )) {
                Label("Mode aîné", systemImage: "textformat.size")
            }
            if viewModel.user?.seniorMode == true {
                Label("Texte très grand et parcours simplifié activés.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.economie)
                    .grenierTransition(.banner)
            }
        } header: {
            Label("Lisibilité", systemImage: "eye")
        } footer: {
            Text("Agrandit tout le texte et garde seulement l'essentiel : ta commande, ta cueillette et ton groupe.")
        }
        .grenierAnimation(.smooth, value: viewModel.user?.seniorMode)
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
