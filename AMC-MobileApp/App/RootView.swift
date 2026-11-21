import SwiftUI

/// Point d'entrée de l'interface : affiche la navigation du portail actif.
/// Relaie aussi `scenePhase` au `NetworkMonitor` (rechargement au retour au premier plan, S-10)
/// et affiche l'indicateur « Hors ligne » quand le réseau est coupé.
struct RootView: View {
    @AppStorage(Portal.storageKey) private var portal: Portal = .family
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bascule animée de portail (T-123), demandée depuis le profil ou le menu du bouton Profil.
    @State private var portalSwitch = PortalSwitchCoordinator()

    private var isOffline: Bool { network?.isOnline == false }

    var body: some View {
        Group {
            switch portal {
            case .family: FamilyTabView()
            case .vendor: VendorTabView()
            }
        }
        .animation(.smooth, value: portal)
        // L'écran du portail recule sous le voile, puis reprend sa place quand le voile s'efface.
        .scaleEffect(portalSwitch.phase.contentScale(reduceMotion: reduceMotion))
        .overlay(alignment: .top) {
            if isOffline {
                OfflineBadge()
                    .padding(.top, 4)
                    // Ne bloque pas les boutons de la barre de navigation en dessous.
                    .allowsHitTesting(false)
                    .grenierTransition(.banner)
            }
        }
        .grenierAnimation(.smooth, value: isOffline)
        .overlay { PortalSplashOverlay(phase: portalSwitch.phase) }
        .environment(portalSwitch)
        .onChange(of: portalSwitch.phase) { _, phase in
            // Le voile couvre l'écran : on change de portail d'un coup, sans animation visible.
            guard case .presenting(let destination) = phase, destination != portal else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { portal = destination }
        }
        .grenierHaptic(.success, trigger: portalSwitch.completedSwitches) { _, count in count > 0 }
        .onChange(of: scenePhase, initial: true) { _, phase in
            network?.scenePhaseChanged(to: phase)
        }
        .onChange(of: isOffline) { _, offline in
            AccessibilityNotification.Announcement(offline ? String(localized: "Hors ligne") : String(localized: "De retour en ligne")).post()
        }
    }
}

#Preview("Clair") {
    RootView()
        .environment(NetworkMonitor(startsMonitoring: false))
}

#Preview("Sombre") {
    RootView()
        .environment(NetworkMonitor(startsMonitoring: false))
        .preferredColorScheme(.dark)
}

#Preview("Hors ligne") {
    RootView()
        .environment(NetworkMonitor(isOnline: false, startsMonitoring: false))
}
