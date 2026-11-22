// SectionLayout.swift
// Sections réorganisables (B-037, E19 Personnalisation) : ordre et masquage des sections d'un écran
// (Accueil famille, tableau vendeur), persistés localement, avec Réinitialiser.
//
// Usage :
//   @AppStorage("home.sections") private var rawLayout = ""
//   let layout = SectionLayout(raw: rawLayout, defaults: HomeSection.allCases.map(\.rawValue))
//   ForEach(layout.visible, id: \.self) { section(for: $0) }
//   .layoutEditorPanel(isPresented: $isEditing, title:, sections: [...], raw: $rawLayout)   // LayoutEditorPanel.swift

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

    /// Sections montrées : en édition, toutes (les masquées restent à leur place, atténuées) ; sinon les visibles.
    func displayed(isEditing: Bool) -> [String] { isEditing ? order : visible }

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
