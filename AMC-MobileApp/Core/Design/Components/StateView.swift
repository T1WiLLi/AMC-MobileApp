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
            ProgressView("Chargement…")
                .accessibilityLabel("Chargement en cours")
                .modifier(StateBackground())
        case .empty:
            ContentUnavailableView(empty.title, systemImage: empty.systemImage, description: Text(empty.message))
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

/// Plein écran sur le fond crème `Fond`, en clair comme en sombre.
private struct StateBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .grenierBackground()
    }
}

/// Vue d'erreur réutilisable : titre, explication et bouton Réessayer si l'erreur est passagère.
struct ErrorStateView: View {
    let error: AppError
    var retry: (() async -> Void)?

    @State private var isRetrying = false

    var body: some View {
        ContentUnavailableView {
            Label(error.title, systemImage: error.systemImage)
                .symbolRenderingMode(.hierarchical)
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
                    } else {
                        Label("Réessayer", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.glass)
                .disabled(isRetrying)
            }
        }
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

#Preview("Contenu") {
    StateView(state: LoadState.loaded(["Riz", "Farine", "Lentilles"])) { items in
        List(items, id: \.self) { Text($0) }
            .scrollContentBackground(.hidden)
            .grenierBackground()
    }
}
