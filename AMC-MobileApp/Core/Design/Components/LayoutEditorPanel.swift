// LayoutEditorPanel.swift
// Édition de la mise en page d'un écran (Accueil famille, tableau vendeur) :
//  - `.isoLayoutEditing(isActive:)` : chaque section passe en vue isométrique, avec le même angle ;
//  - `.layoutEditorPanel(isPresented:…)` : rail étroit à gauche (poignées) sur un fond flou dégradé : réordonner, masquer, réinitialiser.
// L'ordre et la visibilité restent portés par `SectionLayout` (chaîne `raw`, inchangée).

import SwiftUI

/// Une section proposée dans le panneau.
struct SectionInfo: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tint: Color
}

// MARK: - Vue isométrique

/// Réglages de la vue isométrique : les mêmes pour toutes les sections.
enum IsoLayoutStyle {
    /// Inclinaison autour d'un axe diagonal du plan : un coin vers nous, comme une carte posée sur la table.
    static let angle: Double = 38
    static let axis: (x: CGFloat, y: CGFloat, z: CGFloat) = (x: 0.82, y: -0.58, z: 0)
    /// Perspective faible : le texte reste lisible, la profondeur se lit surtout par l'ombre.
    static let perspective: CGFloat = 0.28
    static let scale: CGFloat = 0.8
    /// Décalage vers la droite : l'empilement reste visible à côté du panneau.
    static let shift: CGFloat = 36
    /// Léger zigzag : une carte sur deux est décalée de ± `stagger`.
    static let stagger: CGFloat = 12
    static func staggerOffset(index: Int) -> CGFloat { index.isMultiple(of: 2) ? -stagger : stagger }
    static let dimmedOpacity: Double = 0.38

    static func angle(isActive: Bool, reduceMotion: Bool) -> Double { isActive && !reduceMotion ? angle : 0 }
    static func scale(isActive: Bool, reduceMotion: Bool) -> CGFloat { isActive && !reduceMotion ? scale : 1 }
    static func opacity(isActive: Bool, isDimmed: Bool) -> Double { isActive && isDimmed ? dimmedOpacity : 1 }
}

private struct IsoLayoutEditingModifier: ViewModifier {
    let isActive: Bool
    let isDimmed: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let flat = isActive && reduceMotion
        content
            // Pas de toucher sur la section (carte inclinée) ; le défilement du parent reste actif.
            .allowsHitTesting(!isActive)
            .scaleEffect(IsoLayoutStyle.scale(isActive: isActive, reduceMotion: reduceMotion))
            .rotation3DEffect(
                .degrees(IsoLayoutStyle.angle(isActive: isActive, reduceMotion: reduceMotion)),
                axis: IsoLayoutStyle.axis,
                anchor: .center,
                perspective: IsoLayoutStyle.perspective
            )
            // Sous Reduce Motion : pas de 3D, un simple cadre de mise en évidence.
            .overlay {
                if flat {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.grenier.opacity(0.5), lineWidth: 2)
                        .padding(-4)
                }
            }
            .offset(x: isActive && !reduceMotion ? IsoLayoutStyle.shift + IsoLayoutStyle.staggerOffset(index: index) : 0)
            .shadow(color: .black.opacity(isActive && !reduceMotion ? 0.22 : 0), radius: 12, x: -10, y: 16)
            .opacity(IsoLayoutStyle.opacity(isActive: isActive, isDimmed: isDimmed))
            .padding(.vertical, isActive && !reduceMotion ? 6 : 0)
            .animation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.22), value: isActive)
            .animation(reduceMotion ? nil : .smooth, value: isDimmed)
    }
}

private struct IsoLayoutEditingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Le panneau de mise en page est ouvert : les sections de l'écran sont en vue isométrique.
    var isEditingLayout: Bool {
        get { self[IsoLayoutEditingKey.self] }
        set { self[IsoLayoutEditingKey.self] = newValue }
    }
}

extension View {
    /// Vue isométrique d'une section pendant l'édition de la mise en page : même angle pour toutes,
    /// ressort à l'entrée et à la sortie, ombre portée, section masquée atténuée. Aucune 3D sous Reduce Motion.
    func isoLayoutEditing(isActive: Bool, isDimmed: Bool = false, index: Int = 0) -> some View {
        modifier(IsoLayoutEditingModifier(isActive: isActive, isDimmed: isDimmed, index: index))
    }

    /// Rail latéral gauche de mise en page. À poser sur la `NavigationStack` pour couvrir aussi la barre de navigation.
    func layoutEditorPanel(
        isPresented: Binding<Bool>,
        title: String,
        sections: [SectionInfo],
        raw: Binding<String>
    ) -> some View {
        environment(\.isEditingLayout, isPresented.wrappedValue)
            .toolbarVisibility(isPresented.wrappedValue ? .hidden : .automatic, for: .tabBar)
            .overlay {
                LayoutEditorRail(isPresented: isPresented, title: title, sections: sections, raw: raw)
            }
    }
}

// MARK: - Rail latéral

/// Calculs purs du rail (testés) : glisser une poignée d'un rang à l'autre, fermer d'un balayage.
enum LayoutRailMath {
    /// Rang visé quand on a glissé de `translation` points depuis le rang `start`, dans `0..<count`.
    static func targetIndex(start: Int, translation: CGFloat, pitch: CGFloat, count: Int) -> Int {
        guard count > 0, pitch > 0 else { return 0 }
        let moved = Int((translation / pitch).rounded())
        return min(max(start + moved, 0), count - 1)
    }

    /// Balayage vers la gauche assez long (ou assez vif) : on ferme.
    static func shouldClose(translation: CGFloat, predictedEnd: CGFloat) -> Bool {
        translation < -70 || predictedEnd < -160
    }
}

struct LayoutEditorRail: View {
    @Binding var isPresented: Bool
    let title: String
    let sections: [SectionInfo]
    @Binding var raw: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var dragId: String?
    @State private var dragStart = 0
    @State private var dragTranslation: CGFloat = 0

    private var layout: SectionLayout { SectionLayout(raw: raw, defaults: sections.map(\.id)) }
    private var animation: Animation? { reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.15) }
    private static let railWidth: CGFloat = 64
    private var pitch: CGFloat { dynamicTypeSize.isAccessibilitySize ? 64 : 52 }

    private func update(_ change: (inout SectionLayout) -> Void) {
        var copy = layout
        change(&copy)
        withAnimation(reduceMotion ? nil : .smooth) { raw = copy.raw }
    }

    private func close() {
        withAnimation(animation) { isPresented = false }
        dragId = nil
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if isPresented {
                backdrop
                    .transition(.opacity)
                rail
                    .transition(reduceMotion ? .opacity : .move(edge: .leading))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(title)
                    .accessibilityAddTraits(.isModal)
                    .accessibilityAction(.escape) { close() }
                    .onAppear { AccessibilityNotification.ScreenChanged().post() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(animation, value: isPresented)
        .allowsHitTesting(isPresented)
    }

    // MARK: Fond

    /// Flou le plus fort sur le bord gauche, qui s'estompe jusqu'au clair vers 50 % de la largeur.
    private var backdrop: some View {
        let fade = LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black.opacity(0.6), location: 0.22),
                .init(color: .clear, location: 0.52),
            ],
            startPoint: .leading, endPoint: .trailing
        )
        return ZStack {
            Rectangle().fill(.ultraThinMaterial).mask(fade)
            // Teinte douce (clair/sombre) : garde le rail lisible sans cacher les cartes.
            LinearGradient(
                colors: [Color(uiColor: .systemBackground).opacity(0.55), .clear],
                startPoint: .leading, endPoint: UnitPoint(x: 0.5, y: 0.5)
            )
        }
        .ignoresSafeArea()
        .contentShape(.rect)
        .onTapGesture { close() }
        .gesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                if LayoutRailMath.shouldClose(translation: value.translation.width, predictedEnd: value.predictedEndTranslation.width) { close() }
            }
        )
        .accessibilityHidden(true)
    }

    // MARK: Rail

    private var rail: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            handles
            actions
            Spacer(minLength: 0)
        }
        .frame(width: Self.railWidth)
        .padding(.leading, 6)
        .grenierHaptic(.selection, trigger: raw)
    }

    private var handles: some View {
        let order = layout.order
        return ZStack(alignment: .topLeading) {
            Capsule()
                .fill(Color.texteSecondaire.opacity(0.35))
                .frame(width: 2, height: max(0, CGFloat(order.count - 1) * pitch))
                .padding(.top, pitch / 2)
                .padding(.leading, 3)
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                ForEach(Array(order.enumerated()), id: \.element) { index, id in
                    if let info = sections.first(where: { $0.id == id }) {
                        handle(info, index: index, isHidden: layout.hidden.contains(id))
                    }
                }
            }
        }
    }

    private func handle(_ info: SectionInfo, index: Int, isHidden: Bool) -> some View {
        let isDragged = dragId == info.id
        let lift = isDragged ? dragTranslation - CGFloat(index - dragStart) * pitch : 0
        let showLabel = isDragged && !dynamicTypeSize.isAccessibilitySize
        let isLast = !isHidden && layout.visible.count <= 1
        return HStack(spacing: 4) {
            Capsule().fill(Color.texteSecondaire.opacity(0.6)).frame(width: 8, height: 2).accessibilityHidden(true)
            Button {
                update { $0.toggle(info.id) }
            } label: {
                Image(systemName: info.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isHidden ? Color.texteSecondaire : info.tint)
                    .overlay {
                        if isHidden {
                            Capsule().fill(Color.texteSecondaire).frame(width: 24, height: 2).rotationEffect(.degrees(-45))
                        }
                    }
                    .frame(width: 40, height: 40)
                    .glassEffect(isDragged ? .regular.tint(info.tint.opacity(0.35)).interactive() : .regular, in: .circle)
                    .opacity(isHidden ? 0.6 : 1)
                    .scaleEffect(isDragged ? 1.12 : 1)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(isLast)
            .overlay(alignment: .leading) {
                if showLabel {
                    Text(info.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .glassEffect(.regular, in: .capsule)
                        .fixedSize()
                        .offset(x: 52)
                        .allowsHitTesting(false)
                }
            }
            .contextMenu {
                Button(isHidden ? "Afficher" : "Masquer", systemImage: isHidden ? "eye" : "eye.slash") { update { $0.toggle(info.id) } }
                    .disabled(isLast)
                Button("Monter", systemImage: "arrow.up") { update { $0.shift(info.id, by: -1) } }
                    .disabled(index == 0)
                Button("Descendre", systemImage: "arrow.down") { update { $0.shift(info.id, by: 1) } }
                    .disabled(index == layout.order.count - 1)
            }
            .simultaneousGesture(reorderGesture(id: info.id, index: index))
        }
        .frame(height: pitch)
        .offset(y: lift)
        .zIndex(isDragged ? 1 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(info.title)
        .accessibilityValue(isHidden ? String(localized: "Masquée") : String(localized: "Position \(index + 1) sur \(sections.count)"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if !isLast { update { $0.toggle(info.id) } } }
        .accessibilityAction(named: String(localized: "Monter")) { update { $0.shift(info.id, by: -1) } }
        .accessibilityAction(named: String(localized: "Descendre")) { update { $0.shift(info.id, by: 1) } }
    }

    private func reorderGesture(id: String, index: Int) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                if dragId != id { dragId = id; dragStart = index }
                let current = layout.order.firstIndex(of: id) ?? index
                let target = LayoutRailMath.targetIndex(start: dragStart, translation: value.translation.height, pitch: pitch, count: layout.order.count)
                dragTranslation = value.translation.height
                if target != current {
                    update { $0.shift(id, by: target - current) }
                }
            }
            .onEnded { _ in
                withAnimation(animation) { dragId = nil; dragTranslation = 0 }
            }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button { update { $0.reset() } } label: {
                Image(systemName: "arrow.counterclockwise").frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .disabled(layout.isDefault)
            .accessibilityLabel("Réinitialiser")
            Button { close() } label: {
                Image(systemName: "checkmark").frame(width: 40, height: 40)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(.grenier)
            .accessibilityLabel("Terminé")
        }
        .padding(.top, 6)
    }
}

#Preview("Rail") {
    @Previewable @State var raw = ""
    @Previewable @State var open = true
    VStack(spacing: 16) {
        ForEach(0..<4, id: \.self) { index in
            RoundedRectangle(cornerRadius: 20).fill(Color.grenier.opacity(0.2)).frame(height: 120)
                .isoLayoutEditing(isActive: open, isDimmed: index == 2, index: index)
        }
    }
    .padding()
    .layoutEditorPanel(
        isPresented: $open,
        title: "Modifier l'accueil",
        sections: [
            .init(id: "group", title: "Mon groupe", systemImage: "person.3.fill", tint: .grenier),
            .init(id: "savings", title: "Économies", systemImage: "chart.line.downtrend.xyaxis", tint: .economie),
            .init(id: "orders", title: "Commandes en cours", systemImage: "cart.fill", tint: .grenier),
            .init(id: "offers", title: "Nouveaux lots", systemImage: "sparkles", tint: .solidarite),
        ],
        raw: $raw
    )
}
