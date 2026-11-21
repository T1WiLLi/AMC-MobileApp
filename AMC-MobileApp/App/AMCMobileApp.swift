import SwiftUI
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct AMCMobileApp: App {
    // Créé dans init(), APRÈS la configuration de Firebase : jamais d'initialiseur de propriété qui touche Firebase.
    @State private var session: SessionViewModel
    @State private var appLock = AppLock()
    /// Contexte de base rechargeable depuis l'écran caché (RQ-114, Features/Debug) : dépôts live non résolus
    /// avec Firebase, démo en mémoire en mode `.fake` seulement.
    @State private var demo: DemoEnvironment
    /// Contexte de la personne connectée (S-03, T-127), résolu par `SessionContextGate`.
    @State private var sessionContext: SessionContextStore
    /// Réseau et rechargement automatique (S-10) : lu par `RootView` et `.refreshOnForeground`.
    @State private var network = NetworkMonitor()

    init() {
        // Fake, émulateur ou projet de démo (B-013) : voir `BackendMode` et docs/firebase.md §4.
        let mode = PerfSignposts.measure("launch.backendSetup") { FirebaseSetup.configure() }
        _session = State(initialValue: SessionViewModel(auth: FirebaseSetup.makeAuthService(mode: mode)))
        let demo = DemoEnvironment(context: .launch(mode: mode), mode: mode)
        _demo = State(initialValue: demo)
        let sessionContext = SessionContextStore()
        _sessionContext = State(initialValue: sessionContext)
        // Notifications locales sans serveur (T-107) : iOS réveille l'app, qui compare au dernier état connu.
        // Enregistré pendant le lancement, comme l'exige BGTaskScheduler ; le gestionnaire garde l'objet en vie.
        let lastKnownState = UserDefaultsLastKnownStateStore()
        let backgroundRefresh = BackgroundRefresh(
            coordinator: NotificationCoordinator(scheduler: UserNotificationScheduler(), store: lastKnownState),
            repositories: demo.context.repositories,
            store: lastKnownState,
            // Ménage de la session résolue ; nil tant que personne n'est connecté (aucun id de démo).
            householdId: { sessionContext.householdId }
        )
        backgroundRefresh.register()
        backgroundRefresh.schedule()
        // Démo : -resetOnboarding rejoue l'accueil, -demoFamilyPortal rouvre côté Familles. Ne touche pas Firebase.
        OnboardingKeys.applyLaunchArguments(ProcessInfo.processInfo.arguments)
    }

    var body: some Scene {
        WindowGroup {
            SessionGate(session: session)
                .onAppear { PerfSignposts.markFirstScreen() }
                // Réinitialisation de la démo : dépôts neufs, et `.id` recrée tous les écrans et leurs ViewModels.
                // Thème choisi dans le Profil (B-035) : relié au trait UIKit, re-teint l'app sans recréer les écrans.
                .appThemed()
                .environment(\.appContext, demo.context)
                .environment(sessionContext)
                .environment(demo)
                .environment(network)
                .id(demo.generation)
                .appLock(appLock)
                #if canImport(GoogleSignIn)
                .onOpenURL { url in _ = GIDSignIn.sharedInstance.handle(url) }
                #endif
                #if DEBUG
                // Démo jury : `-GrenierLiveActivityDemo` au lancement démarre la Live Activity
                // et enchaîne palier franchi → en route → arrivée (OrderActivityController).
                // `-GrenierLiveActivityDemoStep 8` règle l'intervalle entre les étapes (5 s par défaut).
                .task {
                    guard ProcessInfo.processInfo.arguments.contains("-GrenierLiveActivityDemo") else { return }
                    let step = UserDefaults.standard.integer(forKey: "GrenierLiveActivityDemoStep")
                    try? await OrderActivityController.shared.startDemo(stepInterval: .seconds(step > 0 ? step : 5))
                }
                #endif
        }
    }
}
