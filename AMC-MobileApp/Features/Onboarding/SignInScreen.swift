import AuthenticationServices
import SwiftUI

/// Écran de connexion : Google, ou courriel et mot de passe (avec vérification du courriel). iOS 26 Liquid Glass.
struct SignInScreen: View {
    let session: SessionViewModel
    @Environment(\.colorScheme) private var colorScheme
    /// Nom, emblème et accroche de la marque (B-032, `Core/Design/Brand/brand.json`).
    @Environment(\.brand) private var brand

    private var isSigningIn: Bool { session.state == .signingIn }

    var body: some View {
        ScrollView {
        VStack(spacing: 32) {

            VStack(spacing: 16) {
                GrenierSymbolScene(
                    symbol: brand.logo.symbol,
                    satellites: [
                        .init("carrot.fill", tint: .economie),
                        .init(GrenierSymbol.groups, tint: .grenier),
                        .init("leaf.fill", tint: .economie),
                        .init(GrenierSymbol.solidarity, tint: .solidarite)
                    ],
                    trigger: isSigningIn
                )

                Text(brand.name)
                    .font(.largeTitle.bold())
                    .fontDesign(.rounded)

                Text(brand.texts.tagline)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                ValuePropositions()
            }
            .padding(.horizontal)
            .padding(.top, 32)

            VStack(spacing: 12) {
                if let message = session.errorMessage {
                    SignInErrorBanner(message: message)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                if AppleSignIn.isEnabled {
                    SignInWithAppleButton(.continue) { request in
                        session.prepareAppleSignIn(request)
                    } onCompletion: { result in
                        Task { await session.completeAppleSignIn(result) }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .clipShape(.capsule)
                    .disabled(isSigningIn)
                    .accessibilityHint("Ouvre la connexion Apple")
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
                    .foregroundStyle(Color.onAccent)
                }
                .buttonStyle(.glassProminent)
                .disabled(isSigningIn)
                .accessibilityHint("Ouvre la connexion Google")

                OrSeparator()
                    .padding(.vertical, 4)

                EmailAuthForm(session: session)

                Label("Connexion sécurisée", systemImage: "lock.shield.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.texteSecondaire)
                    .symbolRenderingMode(.hierarchical)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .grenierBackground()
        .tint(.grenier)
        .animation(.smooth, value: session.errorMessage)
        .sensoryFeedback(.error, trigger: session.errorMessage) { _, new in new != nil }
    }
}

/// Trois promesses de Grenier en pastilles à icône, empilées sous Dynamic Type accessibilité.
private struct ValuePropositions: View {
    var body: some View {
        // Sur une ligne si elles tiennent sans couper, sinon empilées.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips }
                .fixedSize()
            VStack(alignment: .center, spacing: 8) { chips }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var chips: some View {
        chip("Prix de gros", systemImage: GrenierSymbol.savings, tint: .economie)
        chip("Producteurs d'ici", systemImage: GrenierSymbol.impact, tint: .economie)
        chip("Entre voisins", systemImage: GrenierSymbol.groups, tint: .grenier)
    }

    private func chip(_ title: String, systemImage: String, tint: Color) -> some View {
        Label {
            Text(title)
                .foregroundStyle(Color.texte)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: .capsule)
    }
}

/// Erreur de connexion : carte teintée avec icône qui frétille à l'apparition.
private struct SignInErrorBanner: View {
    let message: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.red)
                .symbolEffect(.wiggle, options: .nonRepeating, value: reduceMotion ? false : hasAppeared)
                .accessibilityHidden(true)
            Text(message)
                .foregroundStyle(Color.texte)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.red.opacity(0.1), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Erreur : \(message)")
        .onAppear { hasAppeared = true }
    }
}

/// Séparateur « ou » entre Google et le formulaire courriel.
private struct OrSeparator: View {
    var body: some View {
        HStack(spacing: 12) {
            line
            Text("ou")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.texteSecondaire)
            line
        }
        .accessibilityHidden(true)
    }

    private var line: some View {
        Rectangle()
            .fill(Color.texteSecondaire.opacity(0.3))
            .frame(height: 1)
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
