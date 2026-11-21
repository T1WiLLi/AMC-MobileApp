import SwiftUI

/// Après l'inscription (ou une connexion) par courriel : l'app reste fermée tant que le lien n'a pas été touché.
/// Vérifie tout seul au retour au premier plan (la personne revient de Mail).
struct EmailVerificationScreen: View {
    let session: SessionViewModel

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var email: String { session.pendingVerificationUser?.email ?? "" }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                    .padding(.top, 48)

                if let message = session.verificationMessage {
                    Label(message, systemImage: "info.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.texteSecondaire)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color.surface, in: .rect(cornerRadius: 16))
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                actions
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity)
        .grenierBackground()
        .tint(.grenier)
        .animation(reduceMotion ? nil : .smooth, value: session.verificationMessage)
        .sensoryFeedback(.warning, trigger: session.verificationMessage) { _, new in new != nil }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await session.checkEmailVerification(silent: true) }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 72))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.red, Color.grenier)
                .symbolEffect(.wiggle, options: reduceMotion ? .nonRepeating : .repeat(.periodic(delay: 2.5)), isActive: !reduceMotion)
                .symbolEffect(.bounce, value: session.verificationSentAt)
                .accessibilityHidden(true)

            Text("Vérifie ton courriel")
                .font(.largeTitle.bold())
                .fontDesign(.rounded)
                .multilineTextAlignment(.center)

            Text("On t'a envoyé un lien à \(email). Touche-le pour activer ton compte, puis reviens ici.")
                .font(.body)
                .foregroundStyle(Color.texteSecondaire)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                Task { await session.checkEmailVerification() }
            } label: {
                HStack(spacing: 8) {
                    if session.isCheckingVerification {
                        ProgressView()
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                    }
                    Text("J'ai vérifié mon courriel")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(Color.onAccent)
            }
            .buttonStyle(.glassProminent)
            .disabled(session.isCheckingVerification)

            // Le compte à rebours se redessine chaque seconde.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = session.resendSecondsRemaining(at: context.date)
                Button {
                    Task { await session.resendVerificationEmail() }
                } label: {
                    HStack(spacing: 8) {
                        if session.isSendingVerification {
                            ProgressView()
                        } else {
                            Image(systemName: remaining > 0 ? "clock.arrow.circlepath" : "arrow.clockwise")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        if remaining > 0 {
                            Text("Renvoyer dans \(remaining) s")
                                .monospacedDigit()
                                .contentTransition(.numericText(countsDown: true))
                        } else {
                            Text("Renvoyer le courriel")
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)
                .disabled(remaining > 0 || session.isSendingVerification)
                .animation(.smooth, value: remaining)
                .accessibilityHint(remaining > 0 ? "Possible dans \(remaining) secondes" : "")
            }

            Button(action: openMail) {
                Label("Ouvrir Mail", systemImage: "envelope.open.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)

            Button {
                session.signOut()
            } label: {
                Label("Changer d'adresse", systemImage: "arrow.uturn.backward")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
            .padding(.top, 4)
            .accessibilityHint("Te déconnecte pour utiliser un autre courriel")
        }
    }

    /// Ouvre l'app Mail (boîte de réception) ; à défaut, un nouveau message.
    private func openMail() {
        guard let inbox = URL(string: "message://") else { return }
        openURL(inbox) { accepted in
            if !accepted, let compose = URL(string: "mailto:") {
                openURL(compose)
            }
        }
    }
}

#Preview("À vérifier") {
    EmailVerificationScreen(session: SessionViewModel(auth: FakeAuthService(signedInUser: .unverifiedSample)))
}

#Preview("Sombre") {
    EmailVerificationScreen(session: SessionViewModel(auth: FakeAuthService(signedInUser: .unverifiedSample)))
        .preferredColorScheme(.dark)
}
