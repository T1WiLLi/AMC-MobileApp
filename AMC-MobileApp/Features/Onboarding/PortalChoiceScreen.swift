import SwiftUI

/// Choix du portail après la première connexion (RQ-014) : Familles, Vendeurs, Organismes (T-116), un ou plusieurs.
struct PortalChoiceScreen: View {
    @State private var model: PortalChoiceViewModel
    private let defaults: UserDefaults
    /// Appelé après l'enregistrement du choix.
    private let onFinish: () -> Void

    @Environment(SessionViewModel.self) private var session: SessionViewModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: PortalChoiceViewModel = PortalChoiceViewModel(), defaults: UserDefaults = .standard, onFinish: @escaping () -> Void = {}) {
        _model = State(initialValue: model)
        self.defaults = defaults
        self.onFinish = onFinish
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                VStack(spacing: 12) {
                    ForEach(Array(Portal.allCases.enumerated()), id: \.element) { index, portal in
                        PortalCard(portal: portal, isSelected: model.isSelected(portal)) {
                            withAnimation(reduceMotion ? nil : .smooth) { model.toggle(portal) }
                        }
                        // Les cartes arrivent en cascade, comme les listes de l'app (T-123).
                        .grenierAppear(index: index)
                    }
                }

                Label(model.hint, systemImage: model.choice?.isMultiple == true ? "arrow.left.arrow.right.circle.fill" : "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Color.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                    // Changement net du texte : un fondu superposerait deux phrases.
                    .transaction { $0.animation = nil }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: confirm) {
                Text("Continuer")
                    .font(.headline)
                    .foregroundStyle(model.canContinue ? Color.onAccent : Color.texteSecondaire)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(.grenier)
            .disabled(!model.canContinue)
            .accessibilityHint(model.canContinue ? "Ouvre Grenier" : "Choisis d'abord un portail")
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .grenierBackground()
        .sensoryFeedback(.selection, trigger: model.selection)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let name = session?.currentUser?.displayName.split(separator: " ").first {
                Text("Bienvenue, \(name)")
                    .font(.headline)
                    .foregroundStyle(Color.grenier)
            }
            Text("Comment veux-tu utiliser Grenier ?")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.texte)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Tu pourras changer d'avis à tout moment dans ton profil.")
                .font(.body)
                .foregroundStyle(Color.texteSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func confirm() {
        guard model.confirm(in: defaults) else { return }
        onFinish()
    }
}

#Preview("Clair") {
    PortalChoiceScreen(defaults: UserDefaults(suiteName: "preview-portal-choice")!)
        .environment(SessionViewModel(auth: FakeAuthService(signedInUser: .sample)))
}

#Preview("AX5, les trois") {
    PortalChoiceScreen(
        model: PortalChoiceViewModel(selection: Set(Portal.allCases)),
        defaults: UserDefaults(suiteName: "preview-portal-choice")!
    )
    .environment(SessionViewModel(auth: FakeAuthService(signedInUser: .sample)))
    .dynamicTypeSize(.accessibility5)
}

#Preview("Sombre, les deux") {
    PortalChoiceScreen(
        model: PortalChoiceViewModel(selection: [.family, .vendor]),
        defaults: UserDefaults(suiteName: "preview-portal-choice")!
    )
    .environment(SessionViewModel(auth: FakeAuthService(signedInUser: .sample)))
    .preferredColorScheme(.dark)
}
