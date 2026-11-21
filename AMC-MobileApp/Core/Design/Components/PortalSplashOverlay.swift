import SwiftUI

/// Voile plein écran de la bascule de portail (T-123), posé par `RootView` au-dessus des onglets.
///
/// Un disque Grenier se répand depuis le bouton Profil (en haut à droite), le panier du logo se
/// transforme en icône du portail de destination, puis le nom du portail et sa phrase apparaissent.
/// Sous Reduce Motion : même contenu, en fondu seul. Ignoré par VoiceOver : `PortalSwitchCoordinator`
/// annonce le nouveau portail.
struct PortalSplashOverlay: View {
    let phase: PortalTransitionPhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var scaledBadge: CGFloat = 132

    /// Logo de Grenier montré avant que le portail de destination ne prenne sa place.
    static let logoSymbol = "basket.fill"

    /// Centre du bouton Profil dans la barre de navigation, depuis le coin haut droit de l'écran.
    static let originInset = CGSize(width: 38, height: 78)

    /// Rayon qui couvre tout l'écran depuis `origin` (distance au coin le plus éloigné).
    static func coveringRadius(from origin: CGPoint, in size: CGSize) -> CGFloat {
        let dx = max(origin.x, size.width - origin.x)
        let dy = max(origin.y, size.height - origin.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    private var badgeSide: CGFloat { min(scaledBadge, 180) }
    private var symbol: String {
        guard phase.showsDestination, let destination = phase.destination else { return Self.logoSymbol }
        return destination.systemImage
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let origin = CGPoint(x: size.width - Self.originInset.width, y: Self.originInset.height)
            let radius = Self.coveringRadius(from: origin, in: size)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.grenier.mix(with: .white, by: 0.14), Color.grenier],
                            center: .center,
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                    .frame(width: radius * 2, height: radius * 2)
                    .scaleEffect(phase.coverScale(reduceMotion: reduceMotion))
                    .position(origin)

                content
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(phase.badgeScale(reduceMotion: reduceMotion))
            }
        }
        .ignoresSafeArea()
        .opacity(phase.coverOpacity)
        .allowsHitTesting(phase.blocksTouches)
        .accessibilityHidden(true)
    }

    private var content: some View {
        VStack(spacing: 20) {
            Image(systemName: symbol)
                .font(.system(size: badgeSide * 0.42, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.onAccent)
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace.magic(fallback: .replace.downUp.byLayer)))
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : phase.showsDestination)
                .frame(width: badgeSide, height: badgeSide)
                .background(Color.onAccent.opacity(0.16), in: .circle)
                .overlay {
                    Circle().strokeBorder(Color.onAccent.opacity(0.28), lineWidth: 1.5)
                }

            VStack(spacing: 6) {
                Text("Grenier")
                    .font(.subheadline.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(2)
                    .opacity(0.85)
                // Toujours dans la mise en page (opacité seule) : rien ne saute quand le nom apparaît.
                Text(phase.destination?.title ?? " ")
                    .font(.largeTitle.bold())
                    .fontDesign(.rounded)
                Text(phase.destination?.splashTagline ?? " ")
                    .font(.title3.weight(.medium))
                    .fontDesign(.rounded)
                    .opacity(0.9)
            }
            .foregroundStyle(Color.onAccent)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .opacity(phase.showsDestination ? 1 : 0)
            .offset(y: phase.showsDestination || reduceMotion ? 0 : 14)
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Démo

private struct PortalSplashDemo: View {
    @State private var portal: Portal = .family
    @State private var coordinator = PortalSwitchCoordinator()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            Label("Portail \(portal.title)", systemImage: portal.systemImage)
                .font(.title2.bold())
            Button("Changer de portail", systemImage: "arrow.left.arrow.right") {
                let next: Portal = portal == .family ? .vendor : .family
                coordinator.switchPortal(from: portal, to: next, reduceMotion: reduceMotion)
            }
            .buttonStyle(.glassProminent)
            .tint(.grenier)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
        .scaleEffect(coordinator.phase.contentScale(reduceMotion: reduceMotion))
        .overlay { PortalSplashOverlay(phase: coordinator.phase) }
        .onChange(of: coordinator.phase) { _, phase in
            if case .presenting(let destination) = phase { portal = destination }
        }
    }
}

#Preview("Bascule animée") {
    PortalSplashDemo()
}

#Preview("Voile figé sombre") {
    PortalSplashOverlay(phase: .presenting(.vendor))
        .preferredColorScheme(.dark)
}

#Preview("Voile figé AX5") {
    PortalSplashOverlay(phase: .presenting(.family))
        .dynamicTypeSize(.accessibility5)
}
