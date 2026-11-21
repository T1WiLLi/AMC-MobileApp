import SwiftUI

/// Ce qu'il manque au contexte de la personne connectée pour afficher un écran (S-03, T-127).
/// À utiliser plutôt qu'un id de démo : `if !context.hasGroup { ContextRequirementView(.group) { … } }`.
enum ContextRequirement: Sendable, CaseIterable {
    /// Pas encore de ménage (compte vendeur seul qui ouvre le portail Familles).
    case household
    /// Ménage sans groupe de quartier.
    case group
    /// Compte sans profil vendeur rattaché.
    case vendor

    var title: LocalizedStringKey {
        switch self {
        case .household: "Crée ton ménage"
        case .group: "Rejoins un groupe"
        case .vendor: "Crée ton profil vendeur"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .household:
            "Un ménage regroupe les personnes qui partagent tes achats. Il te faut un ménage pour rejoindre un groupe de quartier."
        case .group:
            "Les lots se commandent à plusieurs : rejoins le groupe de ton quartier pour débloquer les meilleurs prix."
        case .vendor:
            "Ton compte n'est pas encore rattaché à une ferme ou à un commerce. L'équipe Grenier vérifie chaque producteur avant d'ouvrir son portail."
        }
    }

    var systemImage: String {
        switch self {
        case .household: "house.fill"
        case .group: "person.3.sequence.fill"
        case .vendor: "storefront.fill"
        }
    }

    /// Libellé de l'action principale.
    var actionTitle: LocalizedStringKey {
        switch self {
        case .household: "Créer mon ménage"
        case .group: "Trouver un groupe"
        case .vendor: "Revenir au portail Familles"
        }
    }

    var actionImage: String {
        switch self {
        case .household: "plus.circle.fill"
        case .group: "magnifyingglass"
        case .vendor: "arrow.uturn.backward.circle.fill"
        }
    }
}

/// État vide illustré pour un contexte incomplet, avec UNE action principale (`.glassProminent`).
struct ContextRequirementView: View {
    let requirement: ContextRequirement
    var isWorking = false
    /// Erreur de la dernière tentative, affichée sous l'action.
    var error: AppError?
    var action: (() async -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    init(_ requirement: ContextRequirement, isWorking: Bool = false, error: AppError? = nil,
         action: (() async -> Void)? = nil) {
        self.requirement = requirement
        self.isWorking = isWorking
        self.error = error
        self.action = action
    }

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 12) {
                StateIllustration(systemImage: requirement.systemImage)
                    .symbolEffect(.bounce, value: appeared && !reduceMotion)
                Text(requirement.title)
                    .font(.title2.bold())
                    .foregroundStyle(.texte)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
            }
        } description: {
            Text(requirement.message)
        } actions: {
            if let action {
                Button {
                    Task { await action() }
                } label: {
                    if isWorking {
                        ProgressView()
                            .accessibilityLabel("En cours")
                    } else {
                        Label(requirement.actionTitle, systemImage: requirement.actionImage)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(.grenier)
                .disabled(isWorking)
            }
            if let error {
                Label(error.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
        .onAppear { appeared = true }
    }
}

#Preview("Ménage") {
    ContextRequirementView(.household) {}
}

#Preview("Groupe") {
    ContextRequirementView(.group) {}
}

#Preview("Vendeur, sombre") {
    ContextRequirementView(.vendor) {}
        .preferredColorScheme(.dark)
}
