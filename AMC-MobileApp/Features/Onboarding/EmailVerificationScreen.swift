import SwiftUI

/// Après l'inscription (ou une connexion) par courriel : l'app reste fermée tant que le lien n'a pas été touché.
/// Vérifie tout seul au retour au premier plan (la personne revient de Mail).
struct EmailVerificationScreen: View {
    let session: SessionViewModel

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var envelopeSize: CGFloat = 64

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
                .font(.system(size: min(envelopeSize, 96)))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.red, Color.grenier)
                .symbolEffect(.wiggle, options: reduceMotion ? .nonRepeating : .repeat(.periodic(delay: 2.5)), isActive: !reduceMotion)
                .symbolEffect(.bounce, value: session.verificationSentAt)
                .padding(min(envelopeSize, 96) * 0.4)
                .background(Color.grenier.opacity(0.12), in: .circle)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: min(envelopeSize, 96) * 0.38))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.onAccent, Color.economie)
                }
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: min(envelopeSize, 96) * 0.38))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.onAccent, Color.grenier)
                }
                .accessibilityHidden(true)

            Text("Vérifie ton courriel")
                .font(.largeTitle.bold())
                .fontDesign(.rounded)
                .multilineTextAlignment(.center)

            VStack(spacing: 6) {
                Text("On t'a envoyé un lien à")
                    .font(.body)
                    .foregroundStyle(Color.texteSecondaire)
                Label(email, systemImage: "at.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.texte)
                    .symbolRenderingMode(.hierarchical)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.surface, in: .capsule)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)

            steps
        }
    }

    /// Les trois gestes à faire, numérotés avec une icône chacun.
    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            step(1, "Ouvre le courriel de Grenier", systemImage: "envelope.open.fill")
            step(2, "Touche le lien d'activation", systemImage: "link")
            step(3, "Reviens ici : on vérifie tout seul", systemImage: "arrow.uturn.backward.circle.fill")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
    }

    private func step(_ number: Int, _ text: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .frame(minWidth: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .foregroundStyle(Color.texte)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Étape \(number) : \(text)")
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
