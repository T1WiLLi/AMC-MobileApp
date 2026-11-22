import SwiftUI

/// Parcours d'arrivée : présentation (une fois) → connexion → choix du portail (première fois) → app.
struct SessionGate: View {
    let session: SessionViewModel

    @AppStorage(OnboardingKeys.hasSeenIntro) private var hasSeenIntro = false
    @AppStorage(OnboardingKeys.hasChosenPortal) private var hasChosenPortal = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Contexte de la session (T-127) : vidé à la déconnexion pour que le compte suivant reparte de zéro.
    @Environment(SessionContextStore.self) private var contextStore: SessionContextStore?

    private var step: AppFlowStep {
        AppFlowStep.resolve(
            hasSeenIntro: hasSeenIntro,
            isSignedIn: session.currentUser != nil,
            hasChosenPortal: hasChosenPortal,
            needsEmailVerification: session.pendingVerificationUser != nil
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
            case .emailVerification:
                EmailVerificationScreen(session: session)
                    .transition(transition)
            case .portalChoice:
                if let user = session.currentUser {
                    PortalChoiceGate(user: user) { hasChosenPortal = true }
                        .transition(transition)
                }
            case .app:
                if let user = session.currentUser {
                    // Ménage, groupe et vendeur lus depuis users/{uid} avant d'ouvrir l'app (T-127).
                    SessionContextGate(user: user)
                        .transition(.opacity)
                }
            }
        }
        .environment(session)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth, value: step)
        .task { await session.observeSession() }
        .onChange(of: session.currentUser?.id) { _, id in
            if id == nil {
                contextStore?.clear()
                OnboardingKeys.resetPortalChoice()
                hasChosenPortal = false
            }
        }
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

/// Avant le choix du portail : lit le profil (organisme rattaché ?). Un compte d'organisme n'a qu'un portail,
/// Organismes : on l'ouvre directement, sans écran de choix. Les autres comptes voient le choix habituel.
private struct PortalChoiceGate: View {
    let user: AuthUser
    let onChosen: () -> Void

    @Environment(\.appContext) private var base
    @Environment(SessionContextStore.self) private var store: SessionContextStore?
    @State private var showsChoice = false

    var body: some View {
        Group {
            if showsChoice {
                PortalChoiceScreen(onFinish: onChosen)
            } else {
                SessionLoadingView()
            }
        }
        .task(id: user.id) {
            if let store {
                await store.load(for: user, base: base)
                if store.context.hasOrganization {
                    Portal.lockToOrganization()
                    onChosen()
                    return
                }
            }
            showsChoice = true
        }
    }
}

#Preview("Déconnecté") {
    SessionGate(session: SessionViewModel(auth: FakeAuthService()))
}

#Preview("Connecté") {
    SessionGate(session: SessionViewModel(auth: FakeAuthService(signedInUser: .sample)))
}

#Preview("Courriel à vérifier") {
    SessionGate(session: SessionViewModel(auth: FakeAuthService(signedInUser: .unverifiedSample)))
}

#Preview("Sombre") {
    SessionGate(session: SessionViewModel(auth: FakeAuthService()))
        .preferredColorScheme(.dark)
}
