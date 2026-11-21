import SwiftUI

/// Affiche la connexion tant que personne n'est connecté, puis l'app (RootView et ses portails).
struct SessionGate: View {
    let session: SessionViewModel

    var body: some View {
        Group {
            switch session.state {
            case .signedOut, .signingIn:
                SignInScreen(session: session)
            case .signedIn:
                RootView()
            }
        }
        .environment(session)
        .animation(.smooth, value: session.state)
        .task { await session.observeSession() }
    }
}

#Preview("Déconnecté") {
    SessionGate(session: SessionViewModel(auth: FakeAuthService()))
}

#Preview("Connecté") {
    SessionGate(session: SessionViewModel(auth: FakeAuthService(signedInUser: .sample)))
}
