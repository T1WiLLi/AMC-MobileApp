import SwiftUI
import UserNotifications
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
    /// Notification touchée (T-107) : lue par `FamilyTabView` et `GroupsScreen` pour ouvrir le bon écran.
    @State private var notificationRouter: NotificationRouter
    /// Délégué du centre de notifications : le centre le garde en référence faible, l'app le garde en vie.
    private let notificationDelegate: NotificationDelegate
    /// Langue de l'interface (T-171) : choisie dans Préférences, appliquée à toute l'app sans relancer.
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system

    init() {
        // T-171 : langue choisie (ou changée dans les Réglages iOS) avant le premier texte affiché.
        AppLanguage.bootstrap()
        // Le widget suit aussi la langue retenue (elle a pu changer dans les Réglages iOS).
        ExtensionLanguageSync.reloadWidgets()
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
        // Bannières au premier plan et notification touchée → écran de la commande. Posé avant la fin du
        // lancement, comme l'exige iOS pour recevoir la notification qui a ouvert l'app.
        let notificationRouter = NotificationRouter()
        _notificationRouter = State(initialValue: notificationRouter)
        notificationDelegate = NotificationDelegate(router: notificationRouter)
        UNUserNotificationCenter.current().delegate = notificationDelegate
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
        // Visites guidées (FB-19) : -demoTour (Noisette) et -demoVendorTour (Racoonette) les rejouent depuis la carte
        // d'accueil ; rien en tests ni avec -useFakeData sans l'argument de la visite.
        for tour in TourID.allCases { GuidedTour.instance(for: tour).configureAtLaunch() }
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
                // T-171 : changer de langue recrée les écrans, pour que les textes déjà calculés suivent aussi.
                .id(language)
                .environment(inviteLinks)
                .environment(notificationRouter)
                .appLock(appLock)
                // T-171 : `Text("…")` et les formats SwiftUI suivent la langue choisie.
                .environment(\.locale, language.locale)
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
