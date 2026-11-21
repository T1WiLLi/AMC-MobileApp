// Reportable.swift
// Point d'entrée du signalement (T-106, RQ-098).
//
// 1. Vue sans menu contextuel : ajoute « Signaler » dans un `contextMenu`.
//
//     OfferCard(offer: offer)
//         .reportable(target: .offer(id: offer.id, name: offer.title))
//
// 2. Vue qui a déjà un `contextMenu` (un second `contextMenu` le remplacerait) :
//    ajoute `ReportMenuButton` dans le menu existant et présente la feuille plus haut.
//
//     @State private var reportTarget: ReportTarget?
//     …
//     .contextMenu {
//         ShareLink(…)
//         ReportMenuButton(target: .vendor(id: vendor.id, name: vendor.name), selection: $reportTarget)
//     }
//     .reportSheet(item: $reportTarget)
//
// Le dépôt vient de l'environnement (`\.reportRepository`, fake en mémoire par défaut) :
//     .environment(\.reportRepository, InMemoryReportRepository(behavior: .failing()))

import SwiftUI

/// Bouton « Signaler » à mettre dans un menu ; renseigne `selection` pour ouvrir la feuille.
struct ReportMenuButton: View {
    let target: ReportTarget
    @Binding var selection: ReportTarget?

    var body: some View {
        Button("Signaler", systemImage: "flag") { selection = target }
            .accessibilityLabel("Signaler \(target.kind.demonstrative)")
    }
}

private struct ReportableModifier: ViewModifier {
    let target: ReportTarget
    @State private var selection: ReportTarget?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                ReportMenuButton(target: target, selection: $selection)
            }
            .reportSheet(item: $selection)
    }
}

private struct ReportSheetModifier: ViewModifier {
    @Binding var item: ReportTarget?
    @Environment(\.reportRepository) private var repository

    func body(content: Content) -> some View {
        content.sheet(item: $item) { target in
            ReportSheet(target: target, repository: repository)
        }
    }
}

extension View {
    /// Ajoute « Signaler » au menu contextuel (appui long) de la vue.
    func reportable(target: ReportTarget) -> some View {
        modifier(ReportableModifier(target: target))
    }

    /// Présente la feuille de signalement quand `item` n'est pas `nil`.
    func reportSheet(item: Binding<ReportTarget?>) -> some View {
        modifier(ReportSheetModifier(item: item))
    }
}

// MARK: - Preview

private struct ReportableDemo: View {
    var body: some View {
        VStack(spacing: 16) {
            Label("Ferme de la Rive", systemImage: "storefront.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .grenierCard()
                .reportable(target: .vendor(id: "ferme-rive", name: "Ferme de la Rive"))
            Text("Appui long sur la carte pour signaler.")
                .font(.footnote)
                .foregroundStyle(.texteSecondaire)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .grenierBackground()
    }
}

#Preview("Signalable") {
    ReportableDemo()
}

#Preview("Signalable sombre") {
    ReportableDemo()
        .preferredColorScheme(.dark)
}
