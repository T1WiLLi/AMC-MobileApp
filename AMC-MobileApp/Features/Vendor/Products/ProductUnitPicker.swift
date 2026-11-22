import SwiftUI

/// Unité de vente d'un produit : un menu fixe, comme l'unité d'une part à la création d'un lot (`ShareSpec.Unit`).
/// Le modèle garde une chaîne (`Product.unit`) : une ancienne unité libre (« sac de 10 kg ») reste affichée et choisie
/// tant qu'on ne la change pas.
struct ProductUnitPicker: View {
    @Binding var selection: String

    /// Unités proposées, dans l'ordre du menu : celles d'une part de lot, plus la douzaine.
    static let options: [String] = ShareSpec.Unit.allCases.map(\.rawValue) + ["douzaine"]

    static func title(for unit: String) -> String {
        switch unit {
        case "": String(localized: "Choisir")
        case ShareSpec.Unit.piece.rawValue: String(localized: "unité")
        default: unit
        }
    }

    /// Options du menu : l'unité actuelle d'abord si elle vient d'un ancien produit (texte libre).
    static func menuOptions(current: String) -> [String] {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !options.contains(trimmed) else { return options }
        return [trimmed] + options
    }

    var body: some View {
        Picker("Unité de vente", selection: $selection) {
            if selection.isEmpty {
                Text(Self.title(for: "")).tag("")
            }
            ForEach(Self.menuOptions(current: selection), id: \.self) { unit in
                Text(Self.title(for: unit)).tag(unit)
            }
        }
        .pickerStyle(.menu)
        .tint(.grenier)
        .labelsHidden()
        .accessibilityLabel("Unité de vente")
        .accessibilityValue(Self.title(for: selection))
    }
}

#Preview {
    @Previewable @State var unit = ""
    Form { ProductUnitPicker(selection: $unit) }
}
