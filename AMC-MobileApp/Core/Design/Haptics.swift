import SwiftUI

// Haptique du design system Grenier, au-dessus de `.sensoryFeedback`.
//
// | Haptique     | Quand                                                  | Changement visuel obligatoire           |
// | ------------ | ------------------------------------------------------ | --------------------------------------- |
// | `.selection` | Choix de part, filtre, onglet interne, carte touchée   | élément sélectionné mis en évidence     |
// | `.success`   | Palier débloqué, paiement / réservation confirmé       | sceau `checkmark.seal.fill`, message    |
// | `.warning`   | Validation refusée (champ manquant, quantité trop haute)| message sous le champ, bordure          |
// | `.error`     | Échec (réseau, paiement refusé, connexion)             | message d'erreur ou `StateView` d'erreur |
//
// Règles :
// - Jamais d'haptique sans changement visuel équivalent : le retour doit rester perceptible
//   pour qui a coupé les vibrations ou n'a pas le téléphone en main.
// - Une haptique par événement, pas à chaque frame ni à chaque caractère tapé.
// - Le déclencheur est l'état qui change à l'écran (`trigger:`), pas le bouton.
//
// Exemples :
//
//     Picker("Ta part", selection: $share) { … }
//         .grenierHaptic(.selection, trigger: share)
//
//     TierProgressBar(tiers: tiers, committedShares: committed)
//         .grenierHaptic(.success, trigger: currentTier) { old, new in (new ?? 0) > (old ?? 0) }
//
//     Form { … }
//         .grenierHaptic(.warning, trigger: validationMessage) { _, new in new != nil }
//
//     StateView(...)
//         .grenierHaptic(.error, trigger: errorMessage) { _, new in new != nil }

/// Les quatre retours haptiques de Grenier, nommés selon le sens.
enum GrenierHaptic: CaseIterable, Sendable {
    /// Sélection d'une option.
    case selection
    /// Réussite : palier débloqué, paiement ou réservation confirmé.
    case success
    /// Avertissement : validation refusée, action à corriger.
    case warning
    /// Erreur : l'action a échoué.
    case error

    /// Retour système correspondant.
    var feedback: SensoryFeedback {
        switch self {
        case .selection: .selection
        case .success: .success
        case .warning: .warning
        case .error: .error
        }
    }
}

extension View {
    /// Joue l'haptique Grenier à chaque changement de `trigger`.
    func grenierHaptic<Trigger: Equatable>(_ haptic: GrenierHaptic, trigger: Trigger) -> some View {
        sensoryFeedback(haptic.feedback, trigger: trigger)
    }

    /// Joue l'haptique Grenier quand `trigger` change et que `condition(ancien, nouveau)` est vraie.
    func grenierHaptic<Trigger: Equatable>(
        _ haptic: GrenierHaptic,
        trigger: Trigger,
        condition: @escaping (_ oldValue: Trigger, _ newValue: Trigger) -> Bool
    ) -> some View {
        sensoryFeedback(haptic.feedback, trigger: trigger, condition: condition)
    }
}

// MARK: - Démo

private struct HapticsDemo: View {
    @State private var share = 10
    @State private var unlocked = false
    @State private var validation: String?
    @State private var failure: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker("Ta part", selection: $share) {
                ForEach([5, 10, 20], id: \.self) { Text("\($0) kg").tag($0) }
            }
            .pickerStyle(.segmented)
            .grenierHaptic(.selection, trigger: share)

            Button("Débloquer le palier") {
                withGrenierAnimation(.bouncy, reduceMotion: reduceMotion) { unlocked.toggle() }
            }
            .buttonStyle(.glassProminent)
            .grenierHaptic(.success, trigger: unlocked) { _, new in new }
            Label(unlocked ? String(localized: "Palier débloqué !") : String(localized: "Encore 1 famille"), systemImage: "checkmark.seal.fill")
                .symbolEffect(.bounce, value: unlocked)
                .foregroundStyle(unlocked ? Color.grenier : Color.texteSecondaire)

            Button("Valider sans quantité") {
                validation = validation == nil ? String(localized: "Choisis une quantité.") : nil
            }
            .buttonStyle(.glass)
            .grenierHaptic(.warning, trigger: validation) { _, new in new != nil }
            if let validation {
                Text(validation).font(.subheadline).foregroundStyle(Color.grenier)
            }

            Button("Simuler un paiement refusé") {
                failure = failure == nil ? String(localized: "Le paiement n'a pas abouti.") : nil
            }
            .buttonStyle(.glass)
            .grenierHaptic(.error, trigger: failure) { _, new in new != nil }
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.texte)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .grenierBackground()
    }
}

#Preview("Haptique") {
    HapticsDemo()
}

#Preview("Haptique sombre") {
    HapticsDemo()
        .preferredColorScheme(.dark)
}
