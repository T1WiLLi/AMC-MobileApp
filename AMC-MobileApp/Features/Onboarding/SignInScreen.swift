import SwiftUI

/// Écran de connexion et d'inscription (T-124, refonte photo T-201) : un en-tête photo plein cadre (étal de
/// marché) avec le titre et l'accroche, puis une carte crème qui le chevauche — sélecteur Connexion /
/// Inscription, champs groupés, action principale, « ou », Google. La photo reste en place ; la carte défile
/// par-dessus, donc rien ne se coupe en grand texte ou clavier ouvert.
struct SignInScreen: View {
    let session: SessionViewModel
    @State private var mode: EmailAuthForm.Mode = .signIn
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Hauteur de la photo (depuis le haut de l'écran) et recouvrement de la carte sur elle.
    private static let signInHeaderHeight: CGFloat = 292
    private static let signUpHeaderHeight: CGFloat = 232
    private static let cardOverlap: CGFloat = 24

    private var isSigningIn: Bool { session.state == .signingIn }

    /// En très grand texte, le titre et l'accroche demandent plus de place dans la photo.
    private var headerHeight: CGFloat {
        let base = mode == .signIn ? Self.signInHeaderHeight : Self.signUpHeaderHeight
        return dynamicTypeSize.isAccessibilitySize ? base + 110 : base
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: headerHeight - Self.cardOverlap)
                card
            }
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        // Le contenu part du haut de l'écran, comme la photo : la carte la chevauche de 24 exactement.
        .ignoresSafeArea(edges: .top)
        .background(alignment: .top) {
            AuthPhotoHeader(height: headerHeight, cardOverlap: Self.cardOverlap)
        }
        .grenierBackground()
        .tint(.grenier)
        .animation(reduceMotion ? nil : .smooth, value: session.errorMessage)
        .animation(reduceMotion ? nil : .smooth, value: mode)
        .sensoryFeedback(.error, trigger: session.errorMessage) { _, new in new != nil }
        .sensoryFeedback(.selection, trigger: mode)
        .onChange(of: session.errorMessage) { _, new in
            if let new { AccessibilityNotification.Announcement(new).post() }
        }
    }

    /// Carte de contenu : coins hauts arrondis, fond crème de l'app, 14 entre les blocs.
    private var card: some View {
        VStack(spacing: 14) {
            AuthModePicker(mode: $mode)
                .padding(.bottom, 8)

            if let message = session.errorMessage {
                AuthErrorLine(message: message)
                    .transition(.opacity)
            }

            EmailAuthForm(session: session, mode: $mode)

            OrSeparator(title: "ou")

            googleButton

            Text("Gratuit, sans engagement · aucune carte demandée")
                .font(.footnote)
                .foregroundStyle(Color.texteSecondaire)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(.top, 32)
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(AppTheme.fond)
                .frame(maxWidth: .infinity)
        }
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
                Text("Continuer avec Google")
                    .font(.headline)
                    .foregroundStyle(Color.texte)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.surface, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.texteSecondaire.opacity(0.25), lineWidth: 1))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(isSigningIn)
        .accessibilityHint("Ouvre la connexion Google")
    }
}

/// En-tête photo plein cadre : l'étal de marché passe sous la barre d'état, un voile brun foncé monte du bas
/// pour porter le titre et l'accroche. Décoratif : l'image est cachée à VoiceOver, le titre est un en-tête.
private struct AuthPhotoHeader: View {
    let height: CGFloat
    let cardOverlap: CGFloat

    /// Noir brun du voile (#2B1D14) et blancs du texte posé sur la photo, fixes en clair comme en sombre.
    private static let veil = Color(red: 0x2B / 255, green: 0x1D / 255, blue: 0x14 / 255)
    private static let titleColor = Color(red: 0xFB / 255, green: 0xF6 / 255, blue: 0xEE / 255)

    var body: some View {
        Image("IntroSolution")
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.35),
                        .init(color: Self.veil.opacity(0.72), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .accessibilityHidden(true)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Le Grenier")
                        .font(.largeTitle.weight(.heavy))
                        .tracking(-0.6)
                        .foregroundStyle(Self.titleColor)
                        .accessibilityAddTraits(.isHeader)
                    Text("Le gros, à petit prix, entre voisins.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, cardOverlap + 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .ignoresSafeArea(edges: .top)
    }
}

/// Sélecteur Connexion / Inscription : pilule sable, segment actif blanc qui glisse (`matchedGeometryEffect`).
/// En très grand texte, les segments passent l'un sous l'autre pour ne jamais être tronqués.
private struct AuthModePicker: View {
    @Binding var mode: EmailAuthForm.Mode
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 4))
            : AnyLayout(HStackLayout(spacing: 4))
        layout {
            ForEach(EmailAuthForm.Mode.allCases) { segment($0) }
        }
        .padding(5)
        .background(Color.piste, in: .rect(cornerRadius: 26, style: .continuous))
    }

    private func segment(_ candidate: EmailAuthForm.Mode) -> some View {
        let isActive = mode == candidate
        return Button {
            withAnimation(reduceMotion ? nil : .smooth) { mode = candidate }
        } label: {
            Text(candidate.segmentTitle)
                .font(.callout.weight(isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? Color.texte : Color.texteSecondaire)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 21, style: .continuous)
                            .fill(Color.surface)
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 1)
                            .matchedGeometryEffect(id: "activeSegment", in: selection)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
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

/// Erreur de connexion (Google) : une ligne rouge avec son icône, comme sous les champs du formulaire.
private struct AuthErrorLine: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
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
