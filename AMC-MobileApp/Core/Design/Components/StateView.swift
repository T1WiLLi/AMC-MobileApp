import SwiftUI

/// Affiche le bon contenu selon un `LoadState` : chargement, vide, erreur (avec Réessayer) ou contenu.
///
///     StateView(state: viewModel.offers, empty: .init(title: "Aucun lot", systemImage: "shippingbox", message: "…")) {
///         await viewModel.load()
///     } content: { offers in
///         OfferList(offers: offers)
///     }
struct StateView<Value: Sendable, Content: View>: View {
    struct EmptyContent {
        var title: LocalizedStringKey
        var systemImage: String
        var message: LocalizedStringKey
    }

    let state: LoadState<Value>
    var empty: EmptyContent = .init(title: "Rien pour l'instant", systemImage: "tray", message: "Reviens un peu plus tard.")
    var retry: (() async -> Void)?
    @ViewBuilder let content: (Value) -> Content

    init(
        state: LoadState<Value>,
        empty: EmptyContent = .init(title: "Rien pour l'instant", systemImage: "tray", message: "Reviens un peu plus tard."),
        retry: (() async -> Void)? = nil,
        @ViewBuilder content: @escaping (Value) -> Content
    ) {
        self.state = state
        self.empty = empty
        self.retry = retry
        self.content = content
    }

    var body: some View {
        switch state {
        case .idle, .loading:
            loadingView
        case .failed(let error) where error.isCancellation && retry != nil:
            // Chargement annulé parce qu'on a quitté l'onglet pendant qu'il chargeait : au retour, on relance
            // au lieu de laisser « Oups, un problème est survenu » pour de bon (la `.task` de l'écran ne repasse pas).
            // Tâche détachée de la vue : passer à `.loading` change de branche et annulerait une `.task`.
            loadingView
                .onAppear {
                    guard let retry else { return }
                    Task { await retry() }
                }
        case .empty:
            EmptyStateView(title: empty.title, systemImage: empty.systemImage, message: empty.message)
                .modifier(StateBackground())
        case .failed(let error):
            ErrorStateView(error: error, retry: retry)
                .modifier(StateBackground())
        case .loaded(let value):
            // Le contenu gère son fond (`.scrollContentBackground(.hidden).grenierBackground()` pour une List).
            content(value)
        }
    }
}

extension StateView {
    private var loadingView: some View {
        LoadingStateView()
            .modifier(StateBackground())
    }
}

/// Plein écran sur le fond crème `Fond`, en clair comme en sombre.
/// Centré quand ça tient ; aux tailles AX, le message défile au lieu d'être coupé.
private struct StateBackground: ViewModifier {
    func body(content: Content) -> some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content.padding(.vertical) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
    }
}

/// Illustration d'état : un symbole hiérarchique dans une pastille teintée (96 pt, suit Dynamic Type).
struct StateIllustration: View {
    let systemImage: String
    var tint: Color = .grenier

    @ScaledMetric(relativeTo: .largeTitle) private var side: CGFloat = 96

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: min(side, 160) * 0.44))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: min(side, 160), height: min(side, 160))
            .background(tint.opacity(0.12), in: .circle)
            .overlay(Circle().strokeBorder(tint.opacity(0.18), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// Chargement illustré : le lot « respire » (pulse, coupé sous Reduce Motion) au-dessus d'un indicateur.
struct LoadingStateView: View {
    var message: LocalizedStringKey = "Chargement…"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            StateIllustration(systemImage: GrenierSymbol.offers)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            Label {
                Text(message)
            } icon: {
                ProgressView()
            }
            .font(.subheadline)
            .foregroundStyle(.texteSecondaire)
        }
        .padding()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement en cours")
    }
}

/// État vide illustré : symbole dans une pastille Grenier, qui rebondit à l'apparition.
struct EmptyStateView: View {
    let title: LocalizedStringKey
    let systemImage: String
    let message: LocalizedStringKey

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 12) {
                StateIllustration(systemImage: systemImage)
                    .symbolEffect(.bounce, value: appeared && !reduceMotion)
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.texte)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
            }
        } description: {
            Text(message)
        }
        .onAppear { appeared = true }
    }
}

/// Vue d'erreur réutilisable : titre, explication et bouton Réessayer si l'erreur est passagère.
struct ErrorStateView: View {
    let error: AppError
    var retry: (() async -> Void)?

    @State private var isRetrying = false
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 12) {
                StateIllustration(systemImage: error.systemImage)
                    .symbolEffect(.wiggle, value: appeared && !reduceMotion)
                Text(error.title)
                    .font(.title2.bold())
                    .foregroundStyle(.texte)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
            }
        } description: {
            Text(error.message)
        } actions: {
            if error.isRetryable, let retry {
                Button {
                    Task {
                        isRetrying = true
                        await retry()
                        isRetrying = false
                    }
                } label: {
                    if isRetrying {
                        ProgressView()
                            .accessibilityLabel("Nouvel essai en cours")
                    } else {
                        Label("Réessayer", systemImage: "arrow.clockwise")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                .buttonStyle(.glass)
                .tint(.grenier)
                .disabled(isRetrying)
                .accessibilityHint("Relance le chargement")
            }
        }
        .onAppear { appeared = true }
        .grenierHaptic(.error, trigger: appeared) { _, new in new }
    }
}

#Preview("Chargement") {
    StateView(state: LoadState<[String]>.loading) { Text("\($0.count)") }
}

#Preview("Vide") {
    StateView(
        state: LoadState<[String]>.empty,
        empty: .init(title: "Aucun lot", systemImage: "shippingbox", message: "Aucun producteur ne livre encore ton quartier.")
    ) { Text("\($0.count)") }
}

#Preview("Erreur hors ligne") {
    StateView(state: LoadState<[String]>.failed(.offline), retry: { try? await Task.sleep(for: .seconds(1)) }) { Text("\($0.count)") }
}

#Preview("Erreur sombre") {
    StateView(state: LoadState<[String]>.failed(.orderClosed)) { Text("\($0.count)") }
        .preferredColorScheme(.dark)
}

#Preview("Erreur AX5") {
    StateView(state: LoadState<[String]>.failed(.offline), retry: {}) { Text("\($0.count)") }
        .dynamicTypeSize(.accessibility5)
}

#Preview("Vide AX5 sombre") {
    StateView(
        state: LoadState<[String]>.empty,
        empty: .init(title: "Aucun lot", systemImage: "shippingbox", message: "Aucun producteur ne livre encore ton quartier.")
    ) { Text("\($0.count)") }
        .dynamicTypeSize(.accessibility5)
        .preferredColorScheme(.dark)
}

#Preview("Contenu") {
    StateView(state: LoadState.loaded(["Riz", "Farine", "Lentilles"])) { items in
        List(items, id: \.self) { Text($0) }
            .scrollContentBackground(.hidden)
            .grenierBackground()
    }
}
