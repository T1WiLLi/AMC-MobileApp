import AuthenticationServices
import SwiftUI

/// Écran de connexion (T-124, maquette Claude Design « Grenier — Connexion et inscription ») :
/// bandeau orange avec l'accroche en haut, puis une feuille blanche qui monte dessus avec
/// Google et le formulaire courriel. Le passage connexion ↔ inscription se fait par le lien du bas.
struct SignInScreen: View {
    let session: SessionViewModel
    @State private var mode: EmailAuthForm.Mode = .signIn
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Hauteur visible de l'écran (hors zones sûres), pour choisir la taille du bandeau.
    @State private var viewportHeight: CGFloat = 0

    private var isSigningIn: Bool { session.state == .signingIn }

    /// Taille du bandeau : il cède la place pour que la connexion tienne sans défiler.
    /// Le défilement reste possible en très grand texte (Dynamic Type accessibilité).
    private var heroStyle: SignInHero.Style {
        if mode == .signUp || dynamicTypeSize >= .xxLarge { return .minimal }
        let fullHeroNeeds: CGFloat = AppleSignIn.isEnabled ? 760 : 700
        return viewportHeight >= fullHeroNeeds ? .full : .compact
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SignInHero(style: heroStyle)
                sheet
                    .padding(.top, -28)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            // La feuille blanche descend jusqu'en bas même quand le contenu est court.
            .frame(minHeight: viewportHeight, alignment: .top)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .scrollEdgeEffectHidden(true, for: .bottom)
        .background {
            // Orange en haut (débordement du scroll), Surface en bas sous la feuille.
            VStack(spacing: 0) {
                SignInHero.gradient
                Color.surface
            }
            .ignoresSafeArea()
        }
        .tint(.grenier)
        .animation(reduceMotion ? nil : .smooth, value: session.errorMessage)
        .animation(reduceMotion ? nil : .smooth, value: mode)
        .sensoryFeedback(.error, trigger: session.errorMessage) { _, new in new != nil }
    }

    private var sheet: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(mode == .signIn ? "Connecte-toi" : String(localized: "Crée ton compte"))
                    .font(.title2.bold())
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.texte)
                    .contentTransition(.opacity)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("Gratuit, sans engagement")
                    .font(.caption)
                    .foregroundStyle(Color.texteSecondaire)
            }

            if let message = session.errorMessage {
                SignInErrorBanner(message: message)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            if mode == .signIn {
                socialButtons
                OrSeparator(title: "ou avec ton courriel")
            }

            EmailAuthForm(session: session, mode: $mode)

            if mode == .signUp {
                OrSeparator(title: "ou")
                socialButtons
            }

            Spacer(minLength: 0)

            modeSwitch
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(Color.surface)
                .shadow(color: .black.opacity(0.08), radius: 12, y: -4)
        }
    }

    @ViewBuilder private var socialButtons: some View {
        VStack(spacing: 10) {
            if AppleSignIn.isEnabled {
                SignInWithAppleButton(mode == .signIn ? .continue : .signUp) { request in
                    session.prepareAppleSignIn(request)
                } onCompletion: { result in
                    Task { await session.completeAppleSignIn(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .clipShape(.rect(cornerRadius: 16))
                .disabled(isSigningIn)
                .accessibilityHint("Ouvre la connexion Apple")
            }

            Button {
                Task { await session.signInWithGoogle() }
            } label: {
                HStack(spacing: 10) {
                    if isSigningIn {
                        ProgressView()
                    } else {
                        Image(systemName: "g.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.grenier)
                    }
                    Text(mode == .signIn ? String(localized: "Continuer avec Google") : String(localized: "S'inscrire avec Google"))
                        .font(.headline)
                        .foregroundStyle(Color.texte)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.surface, in: .rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.texteSecondaire.opacity(0.25), lineWidth: 1.5)
                }
                .contentShape(.rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(isSigningIn)
            .accessibilityHint("Ouvre la connexion Google")
        }
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
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: mode)
    }
}

/// Bandeau du haut : marque, accroche et illustration en symboles.
/// Trois tailles : complet (grand écran), compact (accroche seule), minimal (marque seule, inscription).
private struct SignInHero: View {
    enum Style { case full, compact, minimal }

    let style: Style
    /// Nom, emblème et accroche de la marque (B-032, `Core/Design/Brand/brand.json`).
    @Environment(\.brand) private var brand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// Dégradé fixe (Grenier clair vers brun) : le texte blanc garde son contraste en clair comme en sombre.
    static let gradient = LinearGradient(
        colors: [
            Color(red: 0xA8 / 255, green: 0x4D / 255, blue: 0x18 / 255),
            Color(red: 0x6E / 255, green: 0x30 / 255, blue: 0x0E / 255)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "house.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.18), in: .rect(cornerRadius: 10))
                Text(brand.name)
                    .font(.headline.weight(.heavy))
                    .fontDesign(.rounded)
            }
            .accessibilityElement(children: .combine)

            if style != .minimal {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Le gros, à petit prix, entre voisins.")
                            .font(style == .full ? .title.weight(.heavy) : .title2.weight(.heavy))
                            .fontDesign(.rounded)
                            .fixedSize(horizontal: false, vertical: true)
                        if style == .full {
                            Text(brand.texts.tagline)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if style == .full {
                        ProduceIllustration(symbol: brand.logo.symbol, appeared: appeared && !reduceMotion)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.top, 14)
                .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                Self.gradient
                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: 260, height: 260)
                    .offset(x: 90, y: -90)
            }
            .ignoresSafeArea(edges: .top)
            .accessibilityHidden(true)
        }
        .onAppear { appeared = true }
    }
}

/// Caisse de produits en symboles SF : panier au centre, légumes et feuille autour.
private struct ProduceIllustration: View {
    let symbol: String
    let appeared: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.14))
                .frame(width: 88, height: 88)
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, options: .nonRepeating, value: appeared)
            badge("carrot.fill", tint: Color(red: 0xE0 / 255, green: 0x6A / 255, blue: 0x2B / 255))
                .offset(x: -38, y: -30)
            badge("leaf.fill", tint: Color(red: 0x2F / 255, green: 0x8A / 255, blue: 0x55 / 255))
                .offset(x: 40, y: -26)
            badge(GrenierSymbol.solidarity, tint: Color(red: 0x6B / 255, green: 0x4F / 255, blue: 0xB3 / 255))
                .offset(x: 34, y: 36)
        }
        .frame(width: 108, height: 108)
        .accessibilityHidden(true)
    }

    private func badge(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(Color(red: 0xFB / 255, green: 0xF7 / 255, blue: 0xF0 / 255), in: .circle)
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}

/// Erreur de connexion (Google, Apple) : carte rouge pâle, icône dans un carré, frétille à l'apparition.
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

/// Séparateur à libellé entre les boutons sociaux et le formulaire.
private struct OrSeparator: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            line
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.texteSecondaire)
                .fixedSize()
            line
        }
        .accessibilityHidden(true)
    }

    private var line: some View {
        Rectangle()
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
