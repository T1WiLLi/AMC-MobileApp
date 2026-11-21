import SwiftUI

/// Petite scène de symboles : un grand symbole dans un disque teinté, entouré de pastilles satellites.
/// Sert d'illustration en tête d'écran et dans les états vides, erreur ou réussite (T-092).
///
///     GrenierSymbolScene(
///         symbol: "basket.fill",
///         satellites: [.init("carrot.fill", tint: .economie), .init("leaf.fill", tint: .economie), .init("house.fill")],
///         trigger: isSignedIn
///     )
///
/// - Le symbole central rebondit une fois à l'apparition puis à chaque changement de `trigger`.
/// - Les satellites entrent en cascade ; sous Reduce Motion, tout apparaît d'un coup, sans rebond.
/// - Taille plafonnée pour ne pas manger l'écran en AX5. Purement décoratif : masqué à VoiceOver.
struct GrenierSymbolScene<Trigger: Equatable>: View {
    struct Satellite: Hashable, Sendable {
        var symbol: String
        var tint: Color

        init(_ symbol: String, tint: Color = .grenier) {
            self.symbol = symbol
            self.tint = tint
        }
    }

    let symbol: String
    var tint: Color = .grenier
    var satellites: [Satellite] = []
    var trigger: Trigger
    /// Version réduite (70 %) pour une feuille ou une carte.
    var isCompact = false

    @ScaledMetric(relativeTo: .largeTitle) private var scaledSide: CGFloat = 96
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    init(symbol: String, tint: Color = .grenier, satellites: [Satellite] = [], trigger: Trigger, isCompact: Bool = false) {
        self.symbol = symbol
        self.tint = tint
        self.satellites = satellites
        self.trigger = trigger
        self.isCompact = isCompact
    }

    /// Grandit avec le texte, sans dépasser 132 pt (92 pt en compact).
    private var side: CGFloat { min(scaledSide, 132) * (isCompact ? 0.7 : 1) }
    private var satelliteSide: CGFloat { side * 0.4 }

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.12))
                .overlay { Circle().strokeBorder(tint.opacity(0.18), lineWidth: 1) }
                .frame(width: side, height: side)

            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: side * 0.5, height: side * 0.5)
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : hasAppeared)
                .symbolEffect(.bounce, options: .nonRepeating, value: trigger)

            ForEach(Array(satellites.prefix(4).enumerated()), id: \.offset) { index, satellite in
                satelliteView(satellite)
                    .offset(offset(for: index))
                    .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.4)
                    .opacity(hasAppeared || reduceMotion ? 1 : 0)
                    .animation(
                        reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.35).delay(0.08 * Double(index + 1)),
                        value: hasAppeared
                    )
            }
        }
        .frame(width: side + satelliteSide, height: side + satelliteSide * 0.6)
        .accessibilityHidden(true)
        .onAppear { hasAppeared = true }
    }

    private func satelliteView(_ satellite: Satellite) -> some View {
        Image(systemName: satellite.symbol)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: satelliteSide * 0.45, weight: .semibold))
            .foregroundStyle(satellite.tint)
            .frame(width: satelliteSide, height: satelliteSide)
            .background(Color.surface, in: .circle)
            .overlay { Circle().strokeBorder(satellite.tint.opacity(0.25), lineWidth: 1) }
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    /// Positions autour du disque : haut-droite, bas-gauche, haut-gauche, bas-droite.
    private func offset(for index: Int) -> CGSize {
        let radius = side * 0.52
        let angles: [Double] = [-40, 140, -140, 40]
        let angle = angles[index % angles.count] * .pi / 180
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
    }
}

extension GrenierSymbolScene where Trigger == Bool {
    /// Scène sans déclencheur : rebondit seulement à l'apparition.
    init(symbol: String, tint: Color = .grenier, satellites: [Satellite] = [], isCompact: Bool = false) {
        self.init(symbol: symbol, tint: tint, satellites: satellites, trigger: false, isCompact: isCompact)
    }
}

/// Titre de section avec icône : symbole teinté hiérarchique + titre gras, trait d'en-tête pour VoiceOver.
///
///     GrenierSectionHeader("Nouveaux lots près de toi", systemImage: "sparkles", tint: .grenier)
struct GrenierSectionHeader: View {
    let title: String
    let systemImage: String
    var tint: Color = .grenier
    var font: Font = .title3.bold()

    init(_ title: String, systemImage: String, tint: Color = .grenier, font: Font = .title3.bold()) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.font = font
    }

    var body: some View {
        Label {
            Text(title)
                .foregroundStyle(Color.texte)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
        .font(font)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Scènes") {
    ScrollView {
        VStack(spacing: 32) {
            GrenierSymbolScene(
                symbol: "basket.fill",
                satellites: [.init("carrot.fill", tint: .economie), .init("leaf.fill", tint: .economie), .init("house.fill")]
            )
            GrenierSymbolScene(
                symbol: "map.fill",
                tint: .solidarite,
                satellites: [.init("person.3.fill"), .init("magnifyingglass", tint: .texteSecondaire)]
            )
            GrenierSectionHeader("Nouveaux lots près de toi", systemImage: "sparkles")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
    }
    .grenierBackground()
}

#Preview("Scènes sombre") {
    GrenierSymbolScene(
        symbol: "envelope.badge.fill",
        satellites: [.init("checkmark.seal.fill", tint: .economie), .init("paperplane.fill")]
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .grenierBackground()
    .preferredColorScheme(.dark)
}

#Preview("Scènes AX5") {
    VStack(spacing: 24) {
        GrenierSymbolScene(symbol: "house.fill", satellites: [.init("person.3.fill"), .init("leaf.fill", tint: .economie)])
        GrenierSectionHeader("Tes commandes en cours", systemImage: "cart.fill")
    }
    .padding()
    .grenierBackground()
    .environment(\.dynamicTypeSize, .accessibility5)
}
