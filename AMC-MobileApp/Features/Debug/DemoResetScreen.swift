import SwiftUI
import UIKit

/// Écran caché « Outils de démo » (RQ-114) : remet la démo du jury à son état initial.
/// S'ouvre par 5 taps ou un appui long sur la version de l'app, dans le Profil (`.demoToolsTrigger()`).
struct DemoResetScreen: View {
    let demo: DemoEnvironment
    /// Optionnel : absent dans les previews. En mode fake, on déconnecte pour rejouer la connexion.
    @Environment(SessionViewModel.self) private var session: SessionViewModel?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isConfirming = false
    @State private var didReset = false
    @State private var copiedCommand: String?

    var body: some View {
        NavigationStack {
            Form {
                backendSection
                switch demo.plan {
                case .reloadFakeData:
                    fakeResetSections
                case let .runSeed(command, explanation):
                    seedSection(command: command, explanation: explanation)
                }
                howToOpenSection
            }
            .navigationTitle("Outils de démo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
            .grenierHaptic(.warning, trigger: isConfirming) { _, new in new }
            .grenierHaptic(.success, trigger: didReset) { _, new in new }
            .grenierHaptic(.selection, trigger: copiedCommand) { _, new in new != nil }
        }
    }

    // MARK: - Sections

    private var backendSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Backend actif")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(demo.mode.title)
                        .font(.headline)
                }
            } icon: {
                Image(systemName: demo.mode.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .imageScale(.large)
            }
            .accessibilityElement(children: .combine)
        } footer: {
            Text("Écran réservé aux répétitions et à la démo du jury. Il n'apparaît pas dans l'app publiée.")
        }
    }

    @ViewBuilder
    private var fakeResetSections: some View {
        Section("Ce qui sera remis à zéro") {
            Label("Lots, commandes et parts rechargés depuis les données de démo", systemImage: "shippingbox.and.arrow.backward")
            Label("Présentation et choix du portail rejoués", systemImage: "hand.wave")
            Label("Compte de démo déconnecté", systemImage: "person.crop.circle.badge.minus")
        }
        .symbolRenderingMode(.hierarchical)

        Section {
            Button(role: .destructive) {
                isConfirming = true
            } label: {
                Label {
                    Text(didReset ? "Démo réinitialisée" : "Réinitialiser la démo")
                } icon: {
                    Image(systemName: didReset ? "checkmark.seal.fill" : "arrow.counterclockwise")
                        .contentTransition(.symbolEffect(.replace))
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(didReset ? .green : .red)
            .disabled(didReset)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .accessibilityHint("Demande une confirmation avant d'effacer la démo en cours.")
            .confirmationDialog(
                "Réinitialiser la démo ?",
                isPresented: $isConfirming,
                titleVisibility: .visible
            ) {
                Button("Réinitialiser", role: .destructive, action: reset)
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Tout ce qui a été fait pendant la démo sera perdu et l'app repartira de l'accueil.")
            }
        }
    }

    private func seedSection(command: String, explanation: String) -> some View {
        Section {
            Text(command)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .padding(.vertical, 4)
                .accessibilityLabel("Commande : \(command)")
            Button {
                UIPasteboard.general.string = command
                withAnimation(.smooth) { copiedCommand = command }
            } label: {
                Label(
                    copiedCommand == command ? "Commande copiée" : "Copier la commande",
                    systemImage: copiedCommand == command ? "checkmark" : "doc.on.doc"
                )
                .contentTransition(.symbolEffect(.replace))
            }
            ShareLink(item: command) {
                Label("Envoyer au Mac", systemImage: "square.and.arrow.up")
            }
        } header: {
            Label("À lancer depuis la racine du repo", systemImage: "terminal")
        } footer: {
            Text("\(explanation) L'app ne vide jamais Firestore elle-même : relance-la ensuite pour repartir de l'accueil.")
        }
    }

    private var howToOpenSection: some View {
        Section {
            Label("5 taps ou appui long sur la version, dans le Profil", systemImage: "hand.tap")
            Label("En Release : argument de lancement \(DemoToolsGate.launchArgument)", systemImage: "terminal")
        } header: {
            Text("Ouvrir cet écran")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .symbolRenderingMode(.hierarchical)
    }

    // MARK: - Action

    /// Coche et haptique d'abord, puis la réinitialisation : elle recrée toute l'arborescence (la feuille se ferme).
    private func reset() {
        withAnimation(.smooth) { didReset = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 300 : 700))
            session?.signOut()
            demo.resetFakeDemo()
        }
    }
}

private extension BackendMode {
    var title: String {
        switch self {
        case .fake: "Données de démo en mémoire"
        case .emulator: "Émulateur Firebase local"
        case .demoProject: "Projet Firebase de démo"
        }
    }

    var systemImage: String {
        switch self {
        case .fake: "memorychip"
        case .emulator: "desktopcomputer"
        case .demoProject: "cloud"
        }
    }
}

#Preview("Fake — clair") {
    DemoResetScreen(demo: DemoEnvironment(context: .instant, mode: .fake))
}

#Preview("Fake — sombre") {
    DemoResetScreen(demo: DemoEnvironment(context: .instant, mode: .fake))
        .preferredColorScheme(.dark)
}

#Preview("Émulateur") {
    DemoResetScreen(demo: DemoEnvironment(context: .instant, mode: .emulator))
}

#Preview("Projet de démo — sombre") {
    DemoResetScreen(demo: DemoEnvironment(context: .instant, mode: .demoProject))
        .preferredColorScheme(.dark)
}
