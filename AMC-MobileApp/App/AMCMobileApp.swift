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
    /// Liens d'invitation reçus (B-058) : lus par `FamilyTabView` et `GroupsScreen`.
    @State private var inviteLinks = InviteLinkRouter()

    init() {
        // Fake, émulateur ou projet de démo (B-013) : voir `BackendMode` et docs/firebase.md §4.
        let mode = PerfSignposts.measure("launch.backendSetup") { FirebaseSetup.configure() }
        _session = State(initialValue: SessionViewModel(auth: FirebaseSetup.makeAuthService(mode: mode)))
        let demo = DemoEnvironment(context: .launch(mode: mode), mode: mode)
        _demo = State(initialValue: demo)
        // Démo de l'onboarding d'après l'inscription (T-156) : seulement sur les données fake, jamais avec Firebase.
        let sessionContext = SessionContextStore(
            forcesOnboarding: mode == .fake
                && ProcessInfo.processInfo.arguments.contains(OnboardingKeys.demoOnboardingArgument),
            // Démo de l'onboarding producteur (T-158) : la démo sans vendeur, données fake seulement.
            forcesVendorOnboarding: mode == .fake
                && ProcessInfo.processInfo.arguments.contains(OnboardingKeys.demoVendorOnboardingArgument)
        )
        _sessionContext = State(initialValue: sessionContext)
        // Notifications locales sans serveur (T-107) : iOS réveille l'app, qui compare au dernier état connu.
        // Enregistré pendant le lancement, comme l'exige BGTaskScheduler ; le gestionnaire garde l'objet en vie.
        let lastKnownState = UserDefaultsLastKnownStateStore()
        let backgroundRefresh = BackgroundRefresh(
            coordinator: NotificationCoordinator(scheduler: UserNotificationScheduler(), store: lastKnownState),
            repositories: demo.context.repositories,
            store: lastKnownState,
            // Ménage de la session résolue ; nil tant que personne n'est connecté (aucun id de démo).
            householdId: { sessionContext.householdId },
            // T-173 : le propriétaire du ménage apprend qu'un compte veut le rejoindre.
            userId: { sessionContext.context.isResolved ? sessionContext.context.userId : nil },
            joinNotifier: HouseholdJoinNotifier()
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
                .environment(inviteLinks)
                .appLock(appLock)
                // Un seul gestionnaire de liens : invitation d'abord (B-058), sinon Google Sign-In.
                .onOpenURL { url in
                    if inviteLinks.handle(url) { return }
                    #if canImport(GoogleSignIn)
                    _ = GIDSignIn.sharedInstance.handle(url)
                    #endif
                }
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
