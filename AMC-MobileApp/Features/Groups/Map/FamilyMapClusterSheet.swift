// FamilyMapClusterSheet.swift
// T-176 (retour samuel) : épingle « pile » quand plusieurs lieux se chevauchent à ce zoom, et la feuille qui
// les liste pour en choisir un. Choisir une ligne fait exactement comme toucher l'épingle du lieu.

import SwiftUI

// MARK: - Textes

nonisolated enum FamilyMapClusterText {
    /// « 3 lieux ici ».
    static func title(count: Int) -> String {
        String(localized: "\(count) lieux ici")
    }

    /// « 2 groupes, 1 producteur » (dans l'ordre des filtres).
    static func breakdown(_ places: [FamilyMapViewModel.Place]) -> String {
        let counts = Dictionary(grouping: places, by: \.kind).mapValues(\.count)
        return FamilyMapViewModel.Kind.allCases.compactMap { kind -> String? in
            guard let count = counts[kind], count > 0 else { return nil }
            return "\(count) \(noun(kind, plural: count > 1))"
        }.joined(separator: ", ")
    }

    /// « 3 lieux ici : 2 groupes, 1 producteur ».
    static func accessibilityLabel(for places: [FamilyMapViewModel.Place]) -> String {
        "\(title(count: places.count)) : \(breakdown(places))"
    }

    private static func noun(_ kind: FamilyMapViewModel.Kind, plural: Bool) -> String {
        switch kind {
        case .group: plural ? String(localized: "groupes") : String(localized: "groupe")
        case .pickupPoint: plural ? String(localized: "points de cueillette") : String(localized: "point de cueillette")
        case .producer: plural ? String(localized: "producteurs") : String(localized: "producteur")
        }
    }
}

// MARK: - Épingle pile

/// Plusieurs épingles empilées : derrière, les pastilles des autres sortes ; devant, la sorte du lieu le plus
/// proche (ou une pile Grenier si les sortes se mélangent) ; en haut à droite, le nombre de lieux.
struct FamilyMapClusterPin: View {
    let kinds: [FamilyMapViewModel.Kind]
    let isSelected: Bool
    let reduceMotion: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 40

    private var diameter: CGFloat { min(size, 60) }
    private var isMixed: Bool { Set(kinds).count > 1 }
    private var frontColor: Color { isMixed ? .grenier : (kinds.first?.color ?? .grenier) }
    private var frontSymbol: String { isMixed ? "square.stack.3d.up.fill" : (kinds.first?.systemImage ?? "mappin") }

    /// Couleurs des pastilles de derrière (deux au plus) : les autres sortes présentes, sinon la même.
    private var backColors: [Color] {
        let others = FamilyMapViewModel.Kind.allCases.filter { kinds.contains($0) && $0 != kinds.first }
        let colors = others.isEmpty ? [frontColor, frontColor] : others.map(\.color)
        return Array(colors.prefix(2))
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ZStack {
                    ForEach(Array(backColors.enumerated().reversed()), id: \.offset) { index, color in
                        disc(color: color)
                            .opacity(0.9)
                            .offset(x: CGFloat(index + 1) * diameter * 0.16, y: -CGFloat(index + 1) * diameter * 0.12)
                    }
                    disc(color: frontColor)
                        .overlay {
                            Image(systemName: frontSymbol)
                                .font(.system(size: diameter * 0.42, weight: .semibold))
                                .foregroundStyle(Color.onAccent)
                                .symbolEffect(.bounce, value: reduceMotion ? false : isSelected)
                        }
                        .overlay {
                            if isSelected { Circle().strokeBorder(Color.texte, lineWidth: 2) }
                        }
                        .overlay(alignment: .topTrailing) { countBadge }
                }
                .shadow(color: .black.opacity(isSelected ? 0.25 : 0.14), radius: isSelected ? 10 : 5, y: 2)
                Capsule()
                    .fill(frontColor)
                    .frame(width: 3, height: 8)
            }
            .scaleEffect(isSelected && !reduceMotion ? 1.12 : 1, anchor: .bottom)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.35), value: isSelected)
    }

    private func disc(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .padding(3)
            .background(Color.surface, in: .circle)
    }

    private var countBadge: some View {
        Text(kinds.count, format: .number)
            .font(.system(size: max(12, diameter * 0.32), weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.surface)
            .padding(.horizontal, 5)
            .frame(minWidth: diameter * 0.5, minHeight: diameter * 0.5)
            .background(Color.texte, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.surface, lineWidth: 2))
            .offset(x: diameter * 0.22, y: -diameter * 0.22)
            .contentTransition(.numericText())
    }
}

// MARK: - Feuille

/// Les lieux d'une pile, du plus proche au plus loin. Une ligne = le même effet que toucher son épingle.
struct FamilyMapClusterSheet: View {
    let places: [FamilyMapViewModel.Place]
    let selectedPlaceID: String?
    /// Faux si les lieux sont au même endroit : zoomer ne les séparerait pas.
    let canZoom: Bool
    let onPick: (FamilyMapViewModel.Place) -> Void
    let onZoom: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(places) { place in
                        Button { onPick(place) } label: {
                            FamilyMapClusterRow(place: place, isSelected: place.id == selectedPlaceID)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.surface)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(place.accessibilityLabel)
                        .accessibilityHint(place.kind == .producer ? "Ouvre la page du producteur" : "Affiche les détails sur la carte")
                        .accessibilityAddTraits(place.id == selectedPlaceID ? [.isButton, .isSelected] : .isButton)
                    }
                } header: {
                    // Résumé discret : aux tailles d'accessibilité, sans icône pour laisser la place à la liste.
                    Label {
                        Text(FamilyMapClusterText.breakdown(places))
                    } icon: {
                        if !dynamicTypeSize.isAccessibilitySize {
                            Image(systemName: "square.stack.3d.up.fill").symbolRenderingMode(.hierarchical)
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .textCase(nil)
                    .foregroundStyle(Color.grenier)
                } footer: {
                    if !canZoom {
                        Label("Ces lieux sont à la même adresse : choisis-en un dans la liste.",
                              systemImage: "mappin.and.ellipse")
                            .foregroundStyle(Color.texteSecondaire)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.fond)
            .navigationTitle(FamilyMapClusterText.title(count: places.count))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", systemImage: "xmark", role: .close) { dismiss() }
                }
                if canZoom {
                    // En face de « Fermer » : l'action secondaire de la feuille, sans masquer la liste.
                    ToolbarItem(placement: .primaryAction) {
                        Button("Zoomer ici", systemImage: "plus.magnifyingglass", action: onZoom)
                            .tint(.grenier)
                            .accessibilityHint("Rapproche la carte pour séparer ces lieux")
                    }
                }
            }
        }
        // Aux tailles d'accessibilité, la liste a besoin de toute la hauteur.
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct FamilyMapClusterRow: View {
    let place: FamilyMapViewModel.Place
    let isSelected: Bool

    @ScaledMetric(relativeTo: .title3) private var badgeSize: CGFloat = 44
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Aux tailles d'accessibilité, l'icône passe au-dessus du texte pour qu'il garde toute la largeur.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 14))
        layout {
            HStack {
                Image(systemName: place.kind.systemImage)
                    // Borné au cercle : le symbole ne déborde pas aux tailles d'accessibilité.
                    .font(.system(size: min(badgeSize, 64) * 0.42, weight: .semibold))
                    .foregroundStyle(Color.onAccent)
                    .frame(width: min(badgeSize, 64), height: min(badgeSize, 64))
                    .background(place.kind.color, in: .circle)
                if dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 0)
                    trailingSymbol
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.headline)
                    .foregroundStyle(Color.texte)
                Text("\(place.kind.title) · \(place.distanceText)")
                    .font(.subheadline)
                    .foregroundStyle(Color.texteSecondaire)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !dynamicTypeSize.isAccessibilitySize { trailingSymbol }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }

    private var trailingSymbol: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
            .font(isSelected ? .title3 : .footnote.weight(.semibold))
            .foregroundStyle(isSelected ? Color.grenier : Color.texteSecondaire)
            .symbolRenderingMode(.hierarchical)
            .contentTransition(.symbolEffect(.replace))
    }
}

// MARK: - Aperçus

#Preview("Épingles pile") {
    HStack(spacing: 40) {
        FamilyMapClusterPin(kinds: [.pickupPoint, .group, .producer], isSelected: false, reduceMotion: false) {}
        FamilyMapClusterPin(kinds: [.producer, .producer], isSelected: true, reduceMotion: false) {}
    }
    .padding(40)
    .background(Color.fond)
}
