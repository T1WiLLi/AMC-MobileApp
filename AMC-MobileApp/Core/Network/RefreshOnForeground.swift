import SwiftUI

extension View {
    /// Recharge l'écran tout seul au retour au premier plan et au retour du réseau (S-10, T-090).
    ///
    /// L'app affiche d'abord les dernières données connues (cache Firestore), puis se met à jour :
    /// pose ce modificateur à côté du `.task` qui fait le premier chargement, avec l'action de rechargement
    /// qui **garde le contenu affiché** (celle du `.refreshable`, pas celle qui repasse par `.loading`).
    ///
    ///     .task { await viewModel.load() }               // premier chargement
    ///     .refreshable { await viewModel.refresh() }     // tirer pour actualiser
    ///     .refreshOnForeground { await viewModel.refresh() }
    ///
    /// - L'action ne part pas à la première apparition (le `.task` vient de charger), seulement quand
    ///   `NetworkMonitor.refreshGeneration` change. Un écran caché (autre onglet) se met à jour en réapparaissant.
    /// - Un nouveau signal annule le rechargement en cours (`.task(id:)`).
    /// - Sans `NetworkMonitor` dans l'environnement (previews, tests), ne fait rien.
    func refreshOnForeground(_ action: @escaping @MainActor () async -> Void) -> some View {
        modifier(RefreshOnForegroundModifier(action: action))
    }
}

private struct RefreshOnForegroundModifier: ViewModifier {
    let action: @MainActor () async -> Void

    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?
    @State private var handledGeneration: Int?

    func body(content: Content) -> some View {
        content.task(id: network?.refreshGeneration) {
            guard let current = network?.refreshGeneration else { return }
            let refreshes = AutoRefreshState.shouldRefresh(lastHandled: handledGeneration, current: current)
            handledGeneration = current
            if refreshes { await action() }
        }
    }
}
