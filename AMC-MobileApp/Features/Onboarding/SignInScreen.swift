import SwiftUI

/// Écran de connexion et d'inscription (T-124, revu en FB-01) : une seule colonne sur le fond crème,
/// dans l'ordre de lecture — marque LeGrenier, titre, champs, action principale, « ou », Google —
/// et le lien qui bascule connexion ↔ inscription posé en bas, au-dessus de la zone sûre.
struct SignInScreen: View {
    let session: SessionViewModel
    @State private var mode: EmailAuthForm.Mode = .signIn
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isSigningIn: Bool { session.state == .signingIn }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                SignInBrandHeader(isCompact: mode == .signUp)

                VStack(spacing: 16) {
                    title

                    if let message = session.errorMessage {
                        SignInErrorBanner(message: message)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    EmailAuthForm(session: session, mode: $mode)
                }

                OrSeparator(title: "ou")

                googleButton
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            modeSwitch
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 4)
        }
        .grenierBackground()
        .tint(.grenier)
        .animation(reduceMotion ? nil : .smooth, value: session.errorMessage)
        .animation(reduceMotion ? nil : .smooth, value: mode)
        .sensoryFeedback(.error, trigger: session.errorMessage) { _, new in new != nil }
    }

    private var title: some View {
        VStack(spacing: 4) {
            Text(mode == .signIn ? String(localized: "Connecte-toi") : String(localized: "Crée ton compte"))
                .font(.title2.bold())
                .fontDesign(.rounded)
                .foregroundStyle(Color.texte)
                .contentTransition(.opacity)
                .accessibilityAddTraits(.isHeader)
            Label("Gratuit, sans engagement", systemImage: "gift.fill")
                .font(.subheadline)
                .foregroundStyle(Color.texteSecondaire)
                .symbolRenderingMode(.hierarchical)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var googleButton: some View {
        Button {
            Task { await session.signInWithGoogle() }
        } label: {
            HStack(spacing: 12) {
                if session.isSigningIn(with: .google) {
                    ProgressView()
                } else {
                    GoogleLogo()
                }
                Text(mode == .signIn ? String(localized: "Continuer avec Google") : String(localized: "S'inscrire avec Google"))
                    .font(.headline)
                    // Couleur de texte explicite : dans un bouton en verre, `.primary` prendrait la teinte.
                    .foregroundStyle(Color.texte)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glass)
        .disabled(isSigningIn)
        .accessibilityHint("Ouvre la connexion Google")
    }

    private var modeSwitch: some View {
        Button {
            mode = mode == .signIn ? .signUp : .signIn
        } label: {
            HStack(spacing: 4) {
                Text(mode == .signIn ? String(localized: "Nouveau ici ?") : String(localized: "Déjà membre ?"))
                    .foregroundStyle(Color.texteSecondaire)
                Text(mode == .signIn ? String(localized: "Créer un compte") : String(localized: "Se connecter"))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.grenier)
            }
            .font(.subheadline)
            .frame(minHeight: 44)
            .contentTransition(.opacity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: mode)
    }
}

/// En-tête de marque : emblème LeGrenier dans un carré au dégradé, nom et accroche.
/// À l'inscription, l'accroche cède sa place pour garder le formulaire visible.
private struct SignInBrandHeader: View {
    let isCompact: Bool
    /// Nom, emblème et accroche de la marque (B-032, `Core/Design/Brand/brand.json`).
    @Environment(\.brand) private var brand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var emblemSide: CGFloat = 72
    @State private var appeared = false

    /// Dégradé fixe (Grenier clair vers brun) : l'emblème blanc garde son contraste en clair comme en sombre.
    private static let gradient = LinearGradient(
        colors: [
            Color(red: 0xC2 / 255, green: 0x5E / 255, blue: 0x22 / 255),
            Color(red: 0x7A / 255, green: 0x35 / 255, blue: 0x10 / 255)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private var side: CGFloat { min(emblemSide, 104) * (isCompact ? 0.78 : 1) }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: brand.logo.symbol)
                .font(.system(size: side * 0.46, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, options: .nonRepeating, value: appeared && !reduceMotion)
                .frame(width: side, height: side)
                .background(Self.gradient, in: .rect(cornerRadius: side * 0.28, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: side * 0.18, weight: .bold))
                        .foregroundStyle(Color.economie)
                        .frame(width: side * 0.36, height: side * 0.36)
                        .background(Color.surface, in: .circle)
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                        .offset(x: side * 0.12, y: -side * 0.12)
                }
                .shadow(color: Color.grenier.opacity(0.3), radius: 12, y: 6)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(brand.name)
                    .font(.largeTitle.weight(.heavy))
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.texte)
                if !isCompact {
                    Text("Le gros, à petit prix, entre voisins.")
                        .font(.subheadline)
                        .foregroundStyle(Color.texteSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .onAppear { appeared = true }
    }
}

/// Logo « G » de Google dessiné en SwiftUI (quatre arcs aux couleurs de la marque et la barre bleue),
/// pour ne pas embarquer d'image téléchargée. Couleurs de la marque Google, fixes en clair comme en sombre.
struct GoogleLogo: View {
    @ScaledMetric(relativeTo: .headline) private var side: CGFloat = 20

    private static let blue = Color(red: 0x42 / 255, green: 0x85 / 255, blue: 0xF4 / 255)
    private static let green = Color(red: 0x34 / 255, green: 0xA8 / 255, blue: 0x53 / 255)
    private static let yellow = Color(red: 0xFB / 255, green: 0xBC / 255, blue: 0x05 / 255)
    private static let red = Color(red: 0xEA / 255, green: 0x43 / 255, blue: 0x35 / 255)

    var body: some View {
        let stroke = side * 0.22
        ZStack {
            // `trim` part de 3 h et tourne dans le sens horaire : bleu en bas à droite, puis vert, jaune, rouge.
            arc(from: 0, to: 0.13, color: Self.blue, width: stroke)
            arc(from: 0.13, to: 0.38, color: Self.green, width: stroke)
            arc(from: 0.38, to: 0.62, color: Self.yellow, width: stroke)
            arc(from: 0.62, to: 0.88, color: Self.red, width: stroke)
            // Barre horizontale du G, du centre jusqu'au bord droit.
            Rectangle()
                .fill(Self.blue)
                .frame(width: side / 2, height: stroke)
                .offset(x: side / 4)
        }
        .padding(stroke / 2)
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    private func arc(from start: CGFloat, to end: CGFloat, color: Color, width: CGFloat) -> some View {
        Circle()
            .trim(from: start, to: end)
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .butt))
    }
}

/// Erreur de connexion (Google) : carte rouge pâle, icône dans un carré, frétille à l'apparition.
private struct SignInErrorBanner: View {
    let message: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.red)
                .frame(width: 32, height: 32)
                .background(Color.red.opacity(0.14), in: .rect(cornerRadius: 10))
                .symbolEffect(.wiggle, options: .nonRepeating, value: reduceMotion ? false : hasAppeared)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.texte)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.red.opacity(0.09), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Erreur : \(message)")
        .onAppear { hasAppeared = true }
    }
}

/// Séparateur « ou » entre le formulaire courriel et Google.
private struct OrSeparator: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            line
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.texteSecondaire)
                .fixedSize()
            line
        }
        .accessibilityHidden(true)
    }

    private var line: some View {
        Capsule()
            .fill(Color.texteSecondaire.opacity(0.25))
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
