// OfferCategoryChips.swift
// Filtre des lots par type de produit, partagé par l'Accueil et la fiche d'un groupe.
// Les comptes et le filtrage viennent de `HomeOfferFilter`.

import SwiftUI

/// Puces « Tous · Céréales · Œufs… » au-dessus d'une liste de lots (nouveaux lots de l'Accueil, lots ouverts d'un groupe), avec le nombre de lots de chaque type.
struct OfferCategoryChips: View {
    let counts: [(category: Product.Category, count: Int)]
    let total: Int
    let selection: Product.Category?
    let reduceMotion: Bool
    let select: (Product.Category?) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    chip(title: String(localized: "Tous"), systemImage: "square.grid.2x2.fill", count: total, value: nil)
                    ForEach(counts, id: \.category) { item in
                        chip(title: item.category.title, systemImage: ProductIcon.symbol(for: item.category),
                             count: item.count, value: item.category)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filtrer par type de produit")
    }

    private func chip(title: String, systemImage: String, count: Int, value: Product.Category?) -> some View {
        let isOn = selection == value
        return Button { select(value) } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.bounce, value: reduceMotion ? false : isOn)
                Text(title)
                Text(count, format: .number)
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .background(isOn ? Color.onAccent.opacity(0.25) : Color.grenier.opacity(0.15), in: .capsule)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isOn ? Color.onAccent : Color.texte)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(isOn ? .regular.tint(.grenier).interactive() : .regular.interactive(), in: .capsule)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
