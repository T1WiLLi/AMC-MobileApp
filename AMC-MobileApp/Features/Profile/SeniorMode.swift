// SeniorMode.swift
// RQ-019 : mode aîné. La préférence vit dans `AppUser.seniorMode` (synchronisée) et est recopiée ici
// dans `@AppStorage` pour que n'importe quelle vue l'applique sans recharger l'utilisateur.
// Usage : `.seniorMode()` une seule fois, à la racine de l'app (`SessionContextGate`) : tout l'arbre
// en hérite, feuilles présentées comprises (l'environnement se propage aux `.sheet`).

import SwiftUI

enum SeniorMode {
    static let storageKey = "grenier.seniorMode"
    /// Texte très grand : jamais plus petit que AX1, jusqu'à AX5.
    static let textSizes: ClosedRange<DynamicTypeSize> = .accessibility1 ... .accessibility5
}

/// Texte très grand et cibles plus grandes (`controlSize(.large)`) quand le mode aîné est actif.
private struct SeniorModeModifier: ViewModifier {
    @AppStorage(SeniorMode.storageKey) private var isOn = false

    func body(content: Content) -> some View {
        if isOn {
            content
                .dynamicTypeSize(SeniorMode.textSizes)
                .controlSize(.large)
        } else {
            content
        }
    }
}

/// Recopie `users/{uid}.seniorMode` dans `@AppStorage` à chaque nouvelle session : la préférence suit le compte,
/// même si la personne n'ouvre jamais Préférences sur cet appareil.
private struct SeniorModeSync: ViewModifier {
    let context: AppContext
    @AppStorage(SeniorMode.storageKey) private var isOn = false

    func body(content: Content) -> some View {
        content.task(id: context.userId) {
            guard context.isResolved,
                  let user = try? await context.repositories.users.user(id: context.userId) else { return }
            if isOn != user.seniorMode { isOn = user.seniorMode }
        }
    }
}

extension View {
    /// Mode aîné : agrandit le texte et les contrôles. À poser une seule fois, à la racine de l'app.
    func seniorMode() -> some View {
        modifier(SeniorModeModifier())
    }

    /// Lit la préférence du compte connecté et l'applique à l'appareil.
    func syncSeniorMode(from context: AppContext) -> some View {
        modifier(SeniorModeSync(context: context))
    }
}

/// Ligne « Mode aîné » du Profil : le même interrupteur que dans Préférences, enregistré dans `users/{uid}`.
struct SeniorModeToggleRow: View {
    @Environment(\.appContext) private var context
    @AppStorage(SeniorMode.storageKey) private var isOn = false
    @State private var viewModel: PreferencesViewModel?

    var body: some View {
        Toggle(isOn: Binding(
            get: { viewModel?.user?.seniorMode ?? isOn },
            set: { newValue in
                isOn = newValue
                Task { await viewModel?.setSeniorMode(newValue) }
            }
        )) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mode aîné")
                    Text("Texte très grand, boutons plus gros")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "textformat.size")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.solidarite)
                    .symbolEffect(.bounce, value: isOn)
                    .accessibilityHidden(true)
            }
        }
        .sensoryFeedback(.selection, trigger: isOn)
        .task(id: context.userId) {
            guard context.isResolved else { return }
            let model = PreferencesViewModel(context: context)
            viewModel = model
            await model.load()
        }
        // Échec de l'enregistrement : le ViewModel revient en arrière, l'appareil aussi.
        .onChange(of: viewModel?.user?.seniorMode) { _, saved in
            if let saved, saved != isOn { isOn = saved }
        }
    }
}

#Preview("Ligne du Profil") {
    NavigationStack {
        List { SeniorModeToggleRow() }
    }
    .environment(\.appContext, .instant)
    .seniorMode()
}
