// LayoutEditorPanel.swift
// Édition de la mise en page d'un écran (Accueil famille, tableau vendeur) :
//  - `.isoLayoutEditing(isActive:)` : chaque section passe en vue isométrique, avec le même angle ;
//  - `.layoutEditorPanel(isPresented:…)` : panneau latéral gauche (glace) pour réordonner, masquer, réinitialiser.
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
    static let scale: CGFloat = 0.7
    /// Décalage vers la droite : l'empilement reste visible à côté du panneau.
    static let shift: CGFloat = 120
    static let dimmedOpacity: Double = 0.38

    static func angle(isActive: Bool, reduceMotion: Bool) -> Double { isActive && !reduceMotion ? angle : 0 }
    static func scale(isActive: Bool, reduceMotion: Bool) -> CGFloat { isActive && !reduceMotion ? scale : 1 }
    static func opacity(isActive: Bool, isDimmed: Bool) -> Double { isActive && isDimmed ? dimmedOpacity : 1 }
}

private struct IsoLayoutEditingModifier: ViewModifier {
    let isActive: Bool
    let isDimmed: Bool
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
            .offset(x: isActive && !reduceMotion ? IsoLayoutStyle.shift : 0)
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
    func isoLayoutEditing(isActive: Bool, isDimmed: Bool = false) -> some View {
        modifier(IsoLayoutEditingModifier(isActive: isActive, isDimmed: isDimmed))
    }

    /// Panneau latéral gauche de mise en page. À poser sur la `NavigationStack` pour couvrir aussi la barre de navigation.
    func layoutEditorPanel(
        isPresented: Binding<Bool>,
        title: String,
        sections: [SectionInfo],
        raw: Binding<String>
    ) -> some View {
        environment(\.isEditingLayout, isPresented.wrappedValue)
            .toolbarVisibility(isPresented.wrappedValue ? .hidden : .automatic, for: .tabBar)
            .overlay {
                LayoutEditorPanel(isPresented: isPresented, title: title, sections: sections, raw: raw)
            }
    }
}

// MARK: - Panneau latéral

struct LayoutEditorPanel: View {
    @Binding var isPresented: Bool
    let title: String
    let sections: [SectionInfo]
    @Binding var raw: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var dragOffset: CGFloat = 0

    private var layout: SectionLayout { SectionLayout(raw: raw, defaults: sections.map(\.id)) }
    private var animation: Animation? { reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.15) }
    private let shape = UnevenRoundedRectangle(bottomTrailingRadius: 32, topTrailingRadius: 32, style: .continuous)

    /// ~72 % de l'écran sur iPhone ; plus étroit sur iPad.
    static func width(in available: CGFloat, isRegular: Bool) -> CGFloat {
        isRegular ? min(380, available * 0.42) : available * 0.72
    }

    /// Balayage vers la gauche assez long (ou assez vif) : on ferme.
    static func shouldClose(translation: CGFloat, predictedEnd: CGFloat) -> Bool {
        translation < -70 || predictedEnd < -160
    }

    private func update(_ change: (inout SectionLayout) -> Void) {
        var copy = layout
        change(&copy)
        withAnimation(reduceMotion ? nil : .smooth) { raw = copy.raw }
    }

    private func close() {
        withAnimation(animation) { isPresented = false }
        dragOffset = 0
    }

    var body: some View {
        GeometryReader { proxy in
            let width = Self.width(in: proxy.size.width, isRegular: horizontalSizeClass == .regular)
            ZStack(alignment: .leading) {
                if isPresented {
                    Color.black
                        .opacity(0.1 * (1 + Double(dragOffset / width)))
                        .ignoresSafeArea()
                        .contentShape(.rect)
                        .onTapGesture { close() }
                        .accessibilityHidden(true)
                        .transition(.opacity)

                    panel
                        .frame(width: width)
                        .frame(maxHeight: .infinity)
                        .background {
                            Color.clear
                                .glassEffect(.regular, in: shape)
                                .ignoresSafeArea()
                        }
                        .offset(x: dragOffset)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 20)
                                .onChanged { value in
                                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                    dragOffset = min(0, value.translation.width)
                                }
                                .onEnded { value in
                                    if Self.shouldClose(translation: value.translation.width, predictedEnd: value.predictedEndTranslation.width) {
                                        close()
                                    } else {
                                        withAnimation(animation) { dragOffset = 0 }
                                    }
                                }
                        )
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
        }
        .allowsHitTesting(isPresented)
    }

    // MARK: Contenu

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            List {
                ForEach(layout.order, id: \.self) { id in
                    if let info = sections.first(where: { $0.id == id }) {
                        row(info, isHidden: layout.hidden.contains(id), position: layout.order.firstIndex(of: id) ?? 0)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(.init(top: 2, leading: 18, bottom: 2, trailing: 6))
                    }
                }
                .onMove { source, destination in update { $0.move(fromOffsets: source, toOffset: destination) } }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
            .grenierHaptic(.selection, trigger: raw)

            Text("Glisse les poignées pour changer l'ordre, touche l'œil pour masquer une section.")
                .font(.footnote)
                .foregroundStyle(Color.texteSecondaire)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            Button(role: .destructive) {
                update { $0.reset() }
            } label: {
                Label("Réinitialiser", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(layout.isDefault)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .padding(.top, 8)
    }

    private var header: some View {
        let isLarge = dynamicTypeSize.isAccessibilitySize
        let arrangement = isLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        return arrangement {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(Color.texte)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !isLarge { Spacer(minLength: 4) }
            Button("Terminé", systemImage: "checkmark") { close() }
                .buttonStyle(.glassProminent)
                .tint(.grenier)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func row(_ info: SectionInfo, isHidden: Bool, position: Int) -> some View {
        HStack(spacing: 10) {
            GrenierIconTile(systemImage: info.systemImage, tint: info.tint, side: 34, shape: .rounded(10), font: .body.weight(.semibold))
                .accessibilityHidden(true)
            Text(info.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isHidden ? Color.texteSecondaire : Color.texte)
                .strikethrough(isHidden, color: .texteSecondaire)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                update { $0.toggle(info.id) }
            } label: {
                Image(systemName: isHidden ? "eye.slash" : "eye.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(isHidden ? Color.texteSecondaire : Color.grenier)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .disabled(!isHidden && layout.visible.count <= 1)
            .accessibilityLabel(isHidden ? String(localized: "Afficher \(info.title)") : String(localized: "Masquer \(info.title)"))
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(isHidden ? String(localized: "Masquée") : String(localized: "Position \(position + 1) sur \(sections.count)"))
        .accessibilityAction(named: String(localized: "Monter")) { update { $0.shift(info.id, by: -1) } }
        .accessibilityAction(named: String(localized: "Descendre")) { update { $0.shift(info.id, by: 1) } }
    }
}

#Preview("Panneau") {
    @Previewable @State var raw = ""
    @Previewable @State var open = true
    VStack(spacing: 16) {
        ForEach(0..<4, id: \.self) { index in
            RoundedRectangle(cornerRadius: 20).fill(Color.grenier.opacity(0.2)).frame(height: 120)
                .isoLayoutEditing(isActive: open, isDimmed: index == 2)
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
