import SwiftUI
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct AMCMobileApp: App {
    // Créé dans init(), APRÈS la configuration de Firebase : jamais d'initialiseur de propriété qui touche Firebase.
    @State private var session: SessionViewModel
    @State private var appLock = AppLock()
    /// Contexte de démo rechargeable depuis l'écran caché (RQ-114, Features/Debug).
    @State private var demo: DemoEnvironment

    init() {
        // Fake, émulateur ou projet de démo (B-013) : voir `BackendMode` et docs/firebase.md §4.
        let mode = PerfSignposts.measure("launch.backendSetup") { FirebaseSetup.configure() }
        _session = State(initialValue: SessionViewModel(auth: FirebaseSetup.makeAuthService(mode: mode)))
        _demo = State(initialValue: DemoEnvironment(mode: mode))
        // Démo : -resetOnboarding rejoue l'accueil, -demoFamilyPortal rouvre côté Familles. Ne touche pas Firebase.
        OnboardingKeys.applyLaunchArguments(ProcessInfo.processInfo.arguments)
    }

    var body: some Scene {
        WindowGroup {
            SessionGate(session: session)
                .onAppear { PerfSignposts.markFirstScreen() }
                // Réinitialisation de la démo : dépôts neufs, et `.id` recrée tous les écrans et leurs ViewModels.
                .environment(\.appContext, demo.context)
                .environment(demo)
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
