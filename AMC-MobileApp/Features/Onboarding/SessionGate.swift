import SwiftUI

/// Parcours d'arrivée : présentation (une fois) → connexion → choix du portail (première fois) → app.
struct SessionGate: View {
    let session: SessionViewModel

    @AppStorage(OnboardingKeys.hasSeenIntro) private var hasSeenIntro = false
    @AppStorage(OnboardingKeys.hasChosenPortal) private var hasChosenPortal = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var step: AppFlowStep {
        AppFlowStep.resolve(
            hasSeenIntro: hasSeenIntro,
            isSignedIn: session.currentUser != nil,
            hasChosenPortal: hasChosenPortal
        )
    }

    var body: some View {
        ZStack {
            switch step {
            case .intro:
                IntroScreen { hasSeenIntro = true }
                    .transition(transition)
            case .signIn:
                SignInScreen(session: session)
                    .transition(transition)
            case .portalChoice:
                PortalChoiceScreen { hasChosenPortal = true }
                    .transition(transition)
            case .app:
                RootView()
                    .transition(.opacity)
            }
        }
        .environment(session)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth, value: step)
        .task { await session.observeSession() }
    }

    /// Glisse vers la gauche d'une étape à l'autre ; simple fondu si Reduce Motion.
    private var transition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }
}

#Preview("Déconnecté") {
    SessionGate(session: SessionViewModel(auth: FakeAuthService()))
}

#Preview("Connecté") {
    SessionGate(session: SessionViewModel(auth: FakeAuthService(signedInUser: .sample)))
}

#Preview("Sombre") {
    SessionGate(session: SessionViewModel(auth: FakeAuthService()))
        .preferredColorScheme(.dark)
}
