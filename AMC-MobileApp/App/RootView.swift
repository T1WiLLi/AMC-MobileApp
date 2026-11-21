import SwiftUI

/// Point d'entrée de l'interface : affiche la navigation du portail actif.
/// Relaie aussi `scenePhase` au `NetworkMonitor` (rechargement au retour au premier plan, S-10)
/// et affiche l'indicateur « Hors ligne » quand le réseau est coupé.
struct RootView: View {
    @AppStorage(Portal.storageKey) private var portal: Portal = .family
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?
    @Environment(\.scenePhase) private var scenePhase

    private var isOffline: Bool { network?.isOnline == false }

    var body: some View {
        Group {
            switch portal {
            case .family: FamilyTabView()
            case .vendor: VendorTabView()
            }
        }
        .animation(.smooth, value: portal)
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
        .onChange(of: scenePhase, initial: true) { _, phase in
            network?.scenePhaseChanged(to: phase)
        }
        .onChange(of: isOffline) { _, offline in
            AccessibilityNotification.Announcement(offline ? "Hors ligne" : "De retour en ligne").post()
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
