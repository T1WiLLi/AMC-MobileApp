import SwiftUI

/// Bascule de portail en capsule de verre (T-123) : « Familles | Vendeurs | Organismes », icônes, pastille Grenier
/// qui glisse vers le portail choisi. Construite depuis une liste de portails : un troisième portail
/// ajoute un segment sans autre changement. Empilée verticalement sous Dynamic Type accessibilité.
struct PortalSegmentedControl: View {
    var portals: [Portal] = Portal.allCases
    let selection: Portal
    let onSelect: (Portal) -> Void

    @Namespace private var pill
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isStacked: Bool { dynamicTypeSize.isAccessibilitySize }
    /// Plus de deux portails sur une ligne : segments plus étroits, icône au-dessus du nom.
    private var isCompactRow: Bool { !isStacked && portals.count > 2 }

    private func segmentIcon(_ portal: Portal, isSelected: Bool) -> some View {
        Image(systemName: portal.systemImage)
            .symbolRenderingMode(.hierarchical)
            .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : isSelected)
    }

    var body: some View {
        let layout = isStacked
            ? AnyLayout(VStackLayout(spacing: 4))
            : AnyLayout(HStackLayout(spacing: 4))
        layout {
            ForEach(portals) { portal in
                segment(portal)
            }
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: isStacked ? AnyShape(.rect(cornerRadius: 28)) : AnyShape(.capsule))
        .grenierAnimation(.snappy, value: selection)
        .grenierHaptic(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Portail")
    }

    private func segment(_ portal: Portal) -> some View {
        let isSelected = portal == selection
        return Button {
            onSelect(portal)
        } label: {
            Group {
                if isCompactRow {
                    // Trois portails côte à côte (T-116) : icône au-dessus du nom pour garder « Organismes » entier.
                    VStack(spacing: 2) {
                        segmentIcon(portal, isSelected: isSelected)
                            .font(.headline)
                        Text(portal.title)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                } else {
                    Label {
                        Text(portal.title)
                            .lineLimit(isStacked ? nil : 1)
                            .minimumScaleFactor(0.8)
                    } icon: {
                        segmentIcon(portal, isSelected: isSelected)
                    }
                    .font(.headline)
                }
            }
            .foregroundStyle(isSelected ? Color.onAccent : Color.texte)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, isCompactRow ? 6 : 12)
            .padding(.vertical, 4)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.grenier)
                        .matchedGeometryEffect(id: "pastille", in: pill)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityHint(isSelected ? "Portail actif" : "Bascule vers le portail \(portal.title.lowercased())")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct PortalSegmentedPreview: View {
    @State private var selection: Portal = .family

    var body: some View {
        VStack(spacing: 16) {
            PortalSegmentedControl(selection: selection) { selection = $0 }
            Text(selection.detail)
                .font(.subheadline)
                .foregroundStyle(Color.texteSecondaire)
        }
        .padding()
        .frame(maxHeight: .infinity)
        .grenierBackground()
    }
}

#Preview("Clair") {
    PortalSegmentedPreview()
}

#Preview("Sombre") {
    PortalSegmentedPreview()
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    PortalSegmentedPreview()
        .dynamicTypeSize(.accessibility5)
}
