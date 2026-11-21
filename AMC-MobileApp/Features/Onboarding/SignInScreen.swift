import SwiftUI

/// Écran de connexion (Google uniquement), iOS 26 Liquid Glass. Les couleurs de marque viendront de B-021.
struct SignInScreen: View {
    let session: SessionViewModel

    private var isSigningIn: Bool { session.state == .signingIn }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "basket.fill")
                    .font(.system(size: 80))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, value: isSigningIn)
                    .accessibilityHidden(true)

                Text("Grenier")
                    .font(.largeTitle.bold())
                    .fontDesign(.rounded)

                Text("Achète en gros avec les familles de ton quartier, directement aux producteurs.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 12) {
                if let message = session.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }

                Button {
                    Task { await session.signInWithGoogle() }
                } label: {
                    HStack(spacing: 8) {
                        if isSigningIn {
                            ProgressView()
                        } else {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                        }
                        Text("Continuer avec Google")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .disabled(isSigningIn)
                .accessibilityHint("Ouvre la connexion Google")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .animation(.smooth, value: session.errorMessage)
        .sensoryFeedback(.error, trigger: session.errorMessage) { _, new in new != nil }
    }
}

#Preview("Clair") {
    SignInScreen(session: SessionViewModel(auth: FakeAuthService()))
}

#Preview("Erreur, sombre") {
    let session = SessionViewModel(auth: FakeAuthService(nextError: .failed("Réseau indisponible. Réessaie.")))
    return SignInScreen(session: session)
        .task { await session.signInWithGoogle() }
        .preferredColorScheme(.dark)
}
