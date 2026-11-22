import SwiftUI

/// Bouton « i » qui ouvre une petite fenêtre d'explication (FB-08).
/// À poser à côté d'un titre de section ou d'un concept clé :
///
///     HStack { Text("Paliers"); InfoButton(topic: .tiers) }
struct InfoButton: View {
    let topic: InfoTopic

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(.body)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        // `.borderless` : dans une ligne de List, seul le « i » réagit, pas toute la ligne.
        .buttonStyle(.borderless)
        .accessibilityLabel(topic.accessibilityLabel)
        .accessibilityHint("Ouvre une courte explication")
        .popover(isPresented: $isPresented) {
            InfoPopoverContent(topic: topic)
                .presentationCompactAdaptation(.popover)
        }
        .sensoryFeedback(.selection, trigger: isPresented) { _, new in new }
    }
}

extension View {
    /// Bouton « i » dans la barre de navigation, pour expliquer l'écran entier (FB-08).
    func infoToolbarButton(_ topic: InfoTopic) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                InfoButton(topic: topic)
            }
        }
    }
}

/// Contenu de la fenêtre : symbole, titre, 2-3 phrases.
struct InfoPopoverContent: View {
    let topic: InfoTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(topic.title)
                    .font(.headline)
                    .foregroundStyle(.texte)
            } icon: {
                Image(systemName: topic.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
            }
            .accessibilityAddTraits(.isHeader)
            Text(topic.message)
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(idealWidth: 300, maxWidth: 320, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Bouton") {
    HStack {
        Text("Paliers de prix").font(.headline)
        InfoButton(topic: .tiers)
    }
    .padding()
}

#Preview("Toutes les explications") {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(InfoTopic.allCases) { topic in
                InfoPopoverContent(topic: topic)
                    .background(.background, in: .rect(cornerRadius: 16))
            }
        }
        .padding()
    }
    .grenierBackground()
}

#Preview("Sombre AX3") {
    InfoPopoverContent(topic: .suspendedBasket)
        .dynamicTypeSize(.accessibility3)
        .preferredColorScheme(.dark)
}
