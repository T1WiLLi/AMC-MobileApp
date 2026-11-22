// GroupsSymbolArt.swift
// Illustrations en SF Symbols de l'onglet Groupes (T-079) : scène de symboles, en-tête de section,
// tuile de chiffre, étiquette d'info, états vide / erreur / chargement illustrés.
// Tout est décoratif et coupe ses animations sous Reduce Motion.

import SwiftUI

// MARK: - Rebond coupé sous Reduce Motion

private struct GroupsBounceModifier<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Sous Reduce Motion la valeur suivie ne change plus : aucun rebond.
        content.symbolEffect(.bounce, value: reduceMotion ? nil : value)
    }
}

extension View {
    /// `.symbolEffect(.bounce, value:)`, sauf sous Reduce Motion.
    func groupsBounce<Value: Equatable>(value: Value) -> some View {
        modifier(GroupsBounceModifier(value: value))
    }
}

// MARK: - Scène de symboles

/// Petite scène : un symbole principal dans un disque teinté, entouré de pastilles satellites.
struct GroupsSymbolScene: View {
    struct Satellite: Hashable {
        var systemImage: String
        var tint: Color
        /// Position autour du disque, en degrés (0 = à droite, -90 = en haut).
        var degrees: Double
    }

    let systemImage: String
    var tint: Color = .grenier
    var satellites: [Satellite] = []
    /// Diamètre du disque à la taille de texte par défaut (suit Dynamic Type, plafonné).
    var diameter: CGFloat = 112
    /// Fond des pastilles : `.surface` sur le fond crème, `.fond` dans une carte.
    var badgeBackground: Color = .surface
    /// Le symbole principal « respire » (coupé sous Reduce Motion).
    var isAnimating = false

    @ScaledMetric(relativeTo: .title) private var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var side: CGFloat { diameter * min(scale, 1.5) }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(tint.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [4, 5]))
                .frame(width: side * 1.3, height: side * 1.3)
            Circle()
                .fill(tint.opacity(0.13))
                .frame(width: side, height: side)
            Image(systemName: systemImage)
                .font(.system(size: side * 0.4, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .symbolEffect(.breathe, isActive: isAnimating && !reduceMotion)
            ForEach(satellites, id: \.self) { satellite in
                let radians = satellite.degrees * .pi / 180
                Image(systemName: satellite.systemImage)
                    .font(.system(size: side * 0.17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(satellite.tint)
                    .frame(width: side * 0.34, height: side * 0.34)
                    .background(badgeBackground, in: .circle)
                    .overlay(Circle().stroke(satellite.tint.opacity(0.28), lineWidth: 1.5))
                    .offset(x: cos(radians) * side * 0.62, y: sin(radians) * side * 0.62)
            }
        }
        .frame(width: side * 1.65, height: side * 1.55)
        .accessibilityHidden(true)
    }
}

// MARK: - En-tête de section

/// Titre de section avec son symbole teinté et, si utile, un compteur animé.
struct GroupsSectionHeader: View {
    let title: String
    let systemImage: String
    var tint: Color = .grenier
    var count: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label {
                Text(LocalizedStringKey(title))
                    .font(.title3.bold())
                    .foregroundStyle(.texte)
            } icon: {
                Image(systemName: systemImage)
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
            }
            Spacer(minLength: 0)
            if let count {
                Text("\(count)")
                    .font(.subheadline.bold())
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(count)))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.14), in: .capsule)
            }
        }
        .grenierAnimation(.smooth, value: count)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Tuile de chiffre clé

/// Chiffre clé (« 27 familles ») : symbole, valeur animée et légende, sur un fond teinté.
struct GroupsStatTile: View {
    let value: String
    let caption: String
    let systemImage: String
    var tint: Color = .grenier

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .groupsBounce(value: value)
            Text(value)
                .font(.title2.bold())
                .fontDesign(.rounded)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.texte)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(LocalizedStringKey(caption))
                .font(.caption)
                .foregroundStyle(.texteSecondaire)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.11), in: .rect(cornerRadius: 16))
        .grenierAnimation(.smooth, value: value)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Étiquette d'info

/// Petite info avec symbole (« 27 familles », « Hochelaga », « 900 m »).
struct GroupsMetaLabel: View {
    let text: String
    let systemImage: String
    var tint: Color = .grenier

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .imageScale(.small)
            Text(text)
                .foregroundStyle(.texteSecondaire)
        }
        .font(.subheadline)
    }
}

// MARK: - États illustrés

/// État vide, d'erreur ou de succès : une scène de symboles, un titre, une explication et des actions.
struct GroupsIllustratedState<Actions: View>: View {
    let scene: GroupsSymbolScene
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 12) {
                scene
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.texte)
                    .accessibilityAddTraits(.isHeader)
            }
        } description: {
            Text(message)
        } actions: {
            actions()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension GroupsIllustratedState where Actions == EmptyView {
    init(scene: GroupsSymbolScene, title: String, message: String) {
        self.init(scene: scene, title: title, message: message) { EmptyView() }
    }
}

/// Erreur illustrée : le symbole de l'erreur au centre, le quartier autour, et « Réessayer » si l'erreur est passagère.
struct GroupsErrorState: View {
    let error: AppError
    var retry: (() async -> Void)?

    @State private var isRetrying = false

    var body: some View {
        GroupsIllustratedState(
            scene: GroupsSymbolScene(
                systemImage: error.systemImage,
                tint: .grenier,
                satellites: [
                    .init(systemImage: GrenierSymbol.groups, tint: .texteSecondaire, degrees: -150),
                    .init(systemImage: "house.fill", tint: .economie, degrees: -30),
                    .init(systemImage: GrenierSymbol.offers, tint: .grenier, degrees: 140)
                ]
            ),
            title: error.title,
            message: error.message
        ) {
            if error.isRetryable, let retry {
                Button {
                    Task {
                        isRetrying = true
                        await retry()
                        isRetrying = false
                    }
                } label: {
                    if isRetrying {
                        ProgressView()
                    } else {
                        Label("Réessayer", systemImage: "arrow.clockwise")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.glass)
                .tint(.grenier)
                .controlSize(.large)
                .disabled(isRetrying)
            }
        }
    }
}

/// Chargement illustré : une scène qui respire au-dessus d'un indicateur et d'un texte.
struct GroupsLoadingScene: View {
    let title: String
    var systemImage: String = GrenierSymbol.groups

    var body: some View {
        VStack(spacing: 16) {
            GroupsSymbolScene(
                systemImage: systemImage,
                satellites: [
                    .init(systemImage: "house.fill", tint: .economie, degrees: -140),
                    .init(systemImage: "mappin", tint: .grenier, degrees: -40),
                    .init(systemImage: GrenierSymbol.offers, tint: .grenier, degrees: 140)
                ],
                isAnimating: true
            )
            Label {
                Text(title)
            } icon: {
                ProgressView()
            }
            .font(.headline)
            .foregroundStyle(.texteSecondaire)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

#if DEBUG
#Preview("Illustrations") {
    ScrollView {
        VStack(spacing: 24) {
            GroupsSectionHeader(title: "Tes groupes", systemImage: "checkmark.seal.fill", tint: .economie, count: 2)
            HStack(spacing: 8) {
                GroupsStatTile(value: "27", caption: "familles", systemImage: "person.2.fill", tint: .solidarite)
                GroupsStatTile(value: "3", caption: "lots ouverts", systemImage: GrenierSymbol.offers)
                GroupsStatTile(value: "900 m", caption: "de rayon", systemImage: "circle.dashed", tint: .economie)
            }
            GroupsMetaLabel(text: "Hochelaga", systemImage: "mappin")
            GroupsLoadingScene(title: "Chargement des groupes…")
                .frame(height: 260)
            GroupsErrorState(error: .offline, retry: { try? await Task.sleep(for: .seconds(1)) })
                .frame(height: 420)
        }
        .padding(16)
    }
    .grenierBackground()
}

#Preview("Illustrations sombre") {
    GroupsErrorState(error: .unknown("démo"), retry: {})
        .grenierBackground()
        .preferredColorScheme(.dark)
}
#endif
