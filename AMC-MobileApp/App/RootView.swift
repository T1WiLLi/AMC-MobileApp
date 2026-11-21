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
    /// Contexte de la session (T-127) : un portail ne s'ouvre que si le compte a ce qu'il lui faut.
    @Environment(\.appContext) private var context
    @Environment(SessionContextStore.self) private var contextStore: SessionContextStore?

    private var isOffline: Bool { network?.isOnline == false }

    var body: some View {
        Group {
            switch portal {
            case .family:
                if context.hasHousehold {
                    FamilyTabView()
                } else {
                    // Compte sans ménage (vendeur seul) : on le crée en un geste, sans id de démo.
                    ContextRequirementView(
                        .household,
                        isWorking: contextStore?.isCreatingHousehold == true,
                        error: contextStore?.householdCreationError
                    ) {
                        await contextStore?.createHousehold()
                    }
                }
            case .vendor:
                if context.hasVendor {
                    VendorTabView()
                } else {
                    // Pas de vendeur rattaché (users/{uid}.vendorId, posé par le seed ou un admin).
                    ContextRequirementView(.vendor) {
                        portalSwitch.switchPortal(from: .vendor, to: .family, reduceMotion: reduceMotion)
                    }
                }
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
            AccessibilityNotification.Announcement(offline ? "Hors ligne" : "De retour en ligne").post()
        }
    }
}

#Preview("Clair") {
    RootView()
        .environment(NetworkMonitor(startsMonitoring: false))
}

#Preview("Sans ménage ni vendeur") {
    var context = AppContext.instant
    context.householdId = ""
    context.groupId = nil
    context.vendorId = ""
    return RootView()
        .environment(\.appContext, context)
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
