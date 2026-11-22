// SectionLayout.swift
// Sections réorganisables (B-037, E19 Personnalisation) : ordre et masquage des sections d'un écran
// (Accueil famille, tableau vendeur), persistés localement, avec Réinitialiser.
//
// Usage :
//   @AppStorage("home.sections") private var rawLayout = ""
//   let layout = SectionLayout(raw: rawLayout, defaults: HomeSection.allCases.map(\.rawValue))
//   ForEach(layout.visible, id: \.self) { section(for: $0) }
//   .sheet { SectionLayoutEditor(title:, sections: [...], raw: $rawLayout) }

import SwiftUI

/// Ordre et sections masquées, encodés en une chaîne pour `@AppStorage` : « a,b,c|b ».
nonisolated struct SectionLayout: Equatable, Sendable {
    var order: [String]
    var hidden: Set<String>
    /// Ordre par défaut de l'écran (aussi la liste des sections connues).
    let defaults: [String]

    init(order: [String], hidden: Set<String>, defaults: [String]) {
        self.defaults = defaults
        // Sections inconnues retirées, sections nouvelles ajoutées à la fin : une mise à jour de l'app
        // qui ajoute une section ne casse pas un ordre enregistré.
        let known = Set(defaults)
        var seen = Set<String>()
        let kept = order.filter { known.contains($0) && seen.insert($0).inserted }
        self.order = kept + defaults.filter { !seen.contains($0) }
        self.hidden = hidden.intersection(known)
    }

    /// Lit une chaîne enregistrée ; vide ou illisible = ordre par défaut.
    init(raw: String, defaults: [String]) {
        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let order = parts.first.map { $0.split(separator: ",").map(String.init) } ?? []
        let hidden = parts.count > 1 ? Set(parts[1].split(separator: ",").map(String.init)) : []
        self.init(order: order, hidden: hidden, defaults: defaults)
    }

    /// Sections affichées, dans l'ordre choisi.
    var visible: [String] { order.filter { !hidden.contains($0) } }

    var isDefault: Bool { order == defaults && hidden.isEmpty }

    var raw: String {
        isDefault ? "" : order.joined(separator: ",") + "|" + hidden.sorted().joined(separator: ",")
    }

    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
    }

    /// Monte (-1) ou descend (+1) une section : actions VoiceOver.
    mutating func shift(_ id: String, by delta: Int) {
        guard let index = order.firstIndex(of: id) else { return }
        let target = index + delta
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
    }

    mutating func toggle(_ id: String) {
        if hidden.contains(id) {
            hidden.remove(id)
        } else if visible.count > 1 {
            // Au moins une section reste visible : jamais d'écran vide.
            hidden.insert(id)
        }
    }

    mutating func reset() {
        order = defaults
        hidden = []
    }
}

// MARK: - Vue inclinée pendant le réarrangement (FB-21)

/// Inclinaison 3D des sections d'un écran pendant que son éditeur de sections est ouvert.
enum SectionArrangeTilt {
    /// Rotation de côté, autour d'un axe presque vertical.
    static let angle: Double = 45
    static let axis: (x: CGFloat, y: CGFloat, z: CGFloat) = (x: 0.12, y: 1, z: 0)
    /// Perspective marquée : le bord éloigné fuit, les sections se lisent comme des cartes posées de biais.
    static let perspective: CGFloat = 0.55
    /// Recul des sections inclinées, pour qu'elles restent dans l'écran.
    static let scale: CGFloat = 0.86

    /// Angle joué : aucun sous Reduce Motion.
    static func angle(isArranging: Bool, reduceMotion: Bool) -> Double {
        isArranging && !reduceMotion ? angle : 0
    }

    /// Échelle jouée : 1 sous Reduce Motion.
    static func scale(isArranging: Bool, reduceMotion: Bool) -> CGFloat {
        isArranging && !reduceMotion ? scale : 1
    }
}

private struct SectionArrangeTiltModifier: ViewModifier {
    let isArranging: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(SectionArrangeTilt.scale(isArranging: isArranging, reduceMotion: reduceMotion))
            .rotation3DEffect(
                .degrees(SectionArrangeTilt.angle(isArranging: isArranging, reduceMotion: reduceMotion)),
                axis: SectionArrangeTilt.axis,
                anchor: .center,
                perspective: SectionArrangeTilt.perspective
            )
            .animation(reduceMotion ? nil : .smooth, value: isArranging)
    }
}

extension View {
    /// Incline la section de ~45° de côté, en perspective, pendant que l'éditeur de sections est ouvert :
    /// au-dessus de la feuille (détente moyenne), l'écran montre l'ordre en train de changer.
    /// Entrée et sortie en `.smooth` ; rien sous Reduce Motion. L'éditeur (glisser pour réordonner) n'est pas touché.
    func sectionArrangeTilt(_ isArranging: Bool) -> some View {
        modifier(SectionArrangeTiltModifier(isArranging: isArranging))
    }
}

// MARK: - Éditeur

/// Une section proposée dans l'éditeur.
struct SectionInfo: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tint: Color
}

/// Feuille « Modifier » : glisser pour réordonner, œil pour masquer, Réinitialiser.
struct SectionLayoutEditor: View {
    let title: String
    let sections: [SectionInfo]
    @Binding var raw: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var layout: SectionLayout { SectionLayout(raw: raw, defaults: sections.map(\.id)) }

    private func update(_ change: (inout SectionLayout) -> Void) {
        var copy = layout
        change(&copy)
        withAnimation(reduceMotion ? nil : .smooth) { raw = copy.raw }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(layout.order, id: \.self) { id in
                        if let info = sections.first(where: { $0.id == id }) {
                            row(info, isHidden: layout.hidden.contains(id), position: layout.order.firstIndex(of: id) ?? 0)
                        }
                    }
                    .onMove { source, destination in update { $0.move(fromOffsets: source, toOffset: destination) } }
                } header: {
                    Label("Sections", systemImage: "rectangle.3.group.fill")
                } footer: {
                    Label("Glisse pour changer l'ordre, touche l'œil pour masquer une section.",
                          systemImage: "hand.draw.fill")
                }

                Section {
                    Button(role: .destructive) {
                        update { $0.reset() }
                    } label: {
                        Label("Réinitialiser", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(layout.isDefault)
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .grenierBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", systemImage: "checkmark") { dismiss() }
                        .buttonStyle(.glassProminent)
                }
            }
            .sensoryFeedback(.selection, trigger: raw)
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ info: SectionInfo, isHidden: Bool, position: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: info.systemImage)
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(info.tint)
                .frame(width: 32, height: 32)
                .background(info.tint.opacity(0.14), in: .rect(cornerRadius: 9))
                .accessibilityHidden(true)
            Text(info.title)
                .foregroundStyle(isHidden ? Color.texteSecondaire : Color.texte)
                .strikethrough(isHidden, color: .texteSecondaire)
            Spacer(minLength: 8)
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
            .accessibilityLabel(isHidden ? "Afficher \(info.title)" : "Masquer \(info.title)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(isHidden ? "Masquée" : "Position \(position + 1) sur \(sections.count)")
        .accessibilityAction(named: "Monter") { update { $0.shift(info.id, by: -1) } }
        .accessibilityAction(named: "Descendre") { update { $0.shift(info.id, by: 1) } }
    }
}

#Preview("Éditeur") {
    @Previewable @State var raw = ""
    SectionLayoutEditor(
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

#Preview("Éditeur sombre") {
    @Previewable @State var raw = "orders,group,savings,offers|savings"
    SectionLayoutEditor(
        title: "Modifier l'accueil",
        sections: [
            .init(id: "group", title: "Mon groupe", systemImage: "person.3.fill", tint: .grenier),
            .init(id: "savings", title: "Économies", systemImage: "chart.line.downtrend.xyaxis", tint: .economie),
            .init(id: "orders", title: "Commandes en cours", systemImage: "cart.fill", tint: .grenier),
            .init(id: "offers", title: "Nouveaux lots", systemImage: "sparkles", tint: .solidarite),
        ],
        raw: $raw
    )
    .preferredColorScheme(.dark)
}
