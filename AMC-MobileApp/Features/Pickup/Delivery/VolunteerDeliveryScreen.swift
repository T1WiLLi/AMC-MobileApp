import SwiftUI

/// RQ-069 (T-117) : livraison à domicile par un voisin bénévole.
/// « Me faire livrer » : un aîné ou une personne à mobilité réduite demande qu'un voisin lui apporte sa part,
/// puis suit la livraison (demandée → prise en charge → en route → livrée).
/// « Livrer un voisin » : les demandes du quartier, la plus proche d'abord, et les livraisons en cours
/// (récupérer chez l'hôte, itinéraire, « Livrée ! » avec haptique et scène de réussite).
struct VolunteerDeliveryScreen: View {
    @State private var viewModel: VolunteerDeliveryViewModel
    @State private var draft: VolunteerDeliveryViewModel.Draft?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: VolunteerDeliveryViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        StateView(state: viewModel.state, retry: { await viewModel.load() }) { content in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Rôle", selection: $viewModel.mode.animation(reduceMotion ? nil : .grenierSmooth)) {
                        ForEach(VolunteerDeliveryViewModel.Mode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .grenierHaptic(.selection, trigger: viewModel.mode)

                    if let error = viewModel.actionError {
                        DeliveryErrorBanner(error: error) { viewModel.dismissError() }
                            .grenierTransition(.banner)
                    }

                    switch viewModel.mode {
                    case .family:
                        DeliveryFamilyView(viewModel: viewModel, content: content) {
                            draft = viewModel.newDraft()
                        }
                        .transition(.opacity)
                    case .volunteer:
                        DeliveryVolunteerView(viewModel: viewModel, content: content)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .refreshable { await viewModel.load() }
            .grenierAnimation(.smooth, value: content)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
        .navigationTitle("Livraison entre voisins")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .task { if viewModel.state.value == nil { await viewModel.load() } }
        .sheet(item: $draft) { draft in
            DeliveryRequestSheet(viewModel: viewModel, draft: draft)
        }
        .overlay {
            if let delivered = viewModel.justDelivered {
                NeighbourSuccessScene(
                    title: "Livré !",
                    message: "Merci ! \(delivered.householdName) a reçu \(FrenchPlural.count(delivered.quantity, "part")) grâce à toi."
                ) {
                    viewModel.justDelivered = nil
                }
                .grenierTransition(.celebration)
            }
        }
        .grenierAnimation(.bouncy, value: viewModel.justDelivered?.id)
        .grenierHaptic(.success, trigger: viewModel.successes)
        .grenierHaptic(.error, trigger: viewModel.actionError) { _, new in new != nil }
    }
}

extension VolunteerDeliveryViewModel.Draft: Identifiable {
    var id: Date { start }
}

// MARK: - Ménage

private struct DeliveryFamilyView: View {
    let viewModel: VolunteerDeliveryViewModel
    let content: VolunteerDeliveryViewModel.Content
    let requestDelivery: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DeliveryFamilyHero(seniorMode: content.seniorMode)
            if let active = content.activeRequest {
                DeliveryTrackingCard(
                    request: active, address: content.addresses[active.id],
                    isPending: viewModel.pendingId == active.id,
                    cancel: { Task { await viewModel.cancel(active) } },
                    confirm: { Task { await viewModel.confirmReceipt(active) } }
                )
                .grenierTransition(.cardAppear)
            } else if content.orderOptions.isEmpty {
                DeliveryEmptyCard(
                    symbol: "basket.fill", satellites: ["house.fill", "figure.walk.cane"],
                    title: "Rien à te faire livrer",
                    message: "Réserve ta part d'un lot : tu pourras ensuite demander qu'un voisin te l'apporte.",
                    actionTitle: "Je livre plutôt un voisin", actionSymbol: "figure.walk"
                ) {
                    viewModel.mode = .volunteer
                }
            } else {
                Button(action: requestDelivery) {
                    Label("Demander une livraison", systemImage: "hand.raised.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.glassProminent)
                .tint(.grenier)
                .disabled(viewModel.isBusy)
                NeighbourInfoLabel(text: "Ton adresse n'est montrée qu'au voisin qui te livre.",
                                   systemImage: "lock.fill", font: .footnote)
            }

            if !content.pastRequests.isEmpty {
                NeighbourSectionHeader(title: "Mes livraisons passées", systemImage: "clock.arrow.circlepath",
                                       count: content.pastRequests.count)
                    .padding(.top, 8)
                ForEach(Array(content.pastRequests.enumerated()), id: \.element.id) { index, request in
                    DeliveryHistoryRow(request: request)
                        .grenierAppear(index: index)
                }
            }
        }
    }
}

private struct DeliveryFamilyHero: View {
    let seniorMode: Bool
    @ScaledMetric(relativeTo: .headline) private var diameter: CGFloat = 72

    var body: some View {
        HStack(spacing: 16) {
            PickupSymbolScene(main: "figure.walk.cane", satellites: ["house.fill", "heart.fill", "basket.fill"],
                              diameter: min(diameter, 110))
            VStack(alignment: .leading, spacing: 6) {
                Text("Un voisin t'apporte ta part")
                    .font(.title3.bold())
                    .foregroundStyle(.texte)
                Text("Pour les aînés et les personnes à mobilité réduite. C'est gratuit, et c'est un voisin du groupe.")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                if seniorMode {
                    NeighbourBadge(text: "Mode aîné activé", systemImage: "checkmark.seal.fill", tint: .economie)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24).fill(Color.surface)
                RoundedRectangle(cornerRadius: 24).fill(
                    LinearGradient(colors: [Color.grenier.opacity(0.14), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Suivi de la demande en cours : étapes, bénévole, créneau, adresse, actions.
private struct DeliveryTrackingCard: View {
    let request: VolunteerDelivery.Request
    let address: VolunteerDelivery.PrivateAddress?
    let isPending: Bool
    let cancel: () -> Void
    let confirm: () -> Void

    @State private var confirmingCancel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                NeighbourSectionHeader(title: "Ma livraison", systemImage: "shippingbox.fill")
                Spacer(minLength: 8)
                NeighbourBadge(text: request.status.title, systemImage: request.status.systemImage,
                               tint: DeliveryStyle.tint(request.status))
            }
            DeliverySteps(steps: VolunteerDelivery.steps(of: request))
            Divider().overlay(Color.piste)
            NeighbourInfoLabel(text: volunteerLine, systemImage: "person.crop.circle.badge.checkmark")
            NeighbourInfoLabel(text: NeighbourHelpFormat.window(start: request.window.start, end: request.window.end),
                               systemImage: "calendar.badge.clock")
            NeighbourInfoLabel(text: FrenchPlural.count(request.quantity, "part"), systemImage: "square.stack.3d.up.fill")
            if let address {
                NeighbourInfoLabel(text: address.address, systemImage: "lock.fill")
            }
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
        .confirmationDialog("Annuler la livraison ?", isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("Annuler la livraison", role: .destructive, action: cancel)
            Button("Garder", role: .cancel) {}
        } message: {
            Text("Tu iras chercher ta part toi-même chez l'hôte.")
        }
    }

    private var volunteerLine: String {
        switch request.status {
        case .requested: "On cherche un voisin pour toi…"
        case .claimed: "\(request.volunteerName ?? "Un voisin") va chercher ta part"
        case .onTheWay: "\(request.volunteerName ?? "Ton voisin") est en route"
        case .delivered: "Livrée par \(request.volunteerName ?? "un voisin")"
        case .cancelled: "Livraison annulée"
        }
    }

    @ViewBuilder private var actions: some View {
        if request.status == .delivered && request.receiptConfirmedAt == nil {
            Button(action: confirm) {
                Label("J'ai bien reçu ma part", systemImage: "hand.thumbsup.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(.economie)
            .disabled(isPending)
        } else if request.status == .requested || request.status == .claimed {
            Button(role: .destructive) { confirmingCancel = true } label: {
                Label("Annuler la demande", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
            .disabled(isPending)
        }
    }
}

/// Étapes verticales : un point par étape, la courante pulse.
private struct DeliverySteps: View {
    let steps: [VolunteerDelivery.Step]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Image(systemName: step.isDone ? step.status.systemImage : "circle")
                            .font(.body)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(step.isDone ? DeliveryStyle.tint(step.status) : Color.texteSecondaire)
                            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                            .symbolEffect(.pulse, options: .repeating, isActive: step.isCurrent && !reduceMotion)
                            .frame(width: 28, height: 28)
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(steps[index + 1].isDone ? Color.economie : Color.piste)
                                .frame(width: 2, height: 18)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.status.title)
                            .font(step.isCurrent ? .subheadline.bold() : .subheadline)
                            .foregroundStyle(step.isDone ? Color.texte : Color.texteSecondaire)
                        if let date = step.date, step.isDone {
                            Text(NeighbourHelpFormat.hour(date)).font(.caption).foregroundStyle(.texteSecondaire)
                        }
                    }
                    .padding(.top, 4)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(step.isDone ? "Fait" : "À venir")
            }
        }
    }
}

private struct DeliveryHistoryRow: View {
    let request: VolunteerDelivery.Request

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: request.status.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DeliveryStyle.tint(request.status))
                .frame(width: 36, height: 36)
                .background(DeliveryStyle.tint(request.status).opacity(0.12), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(NeighbourHelpFormat.window(start: request.window.start, end: request.window.end))
                    .font(.subheadline).foregroundStyle(.texte)
                Text(request.volunteerName.map { "\(request.status.title) · \($0)" } ?? request.status.title)
                    .font(.caption).foregroundStyle(.texteSecondaire)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard(padding: 12)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Bénévole

private struct DeliveryVolunteerView: View {
    let viewModel: VolunteerDeliveryViewModel
    let content: VolunteerDeliveryViewModel.Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DeliveryVolunteerStats(content: content)

            if !content.activeDeliveries.isEmpty {
                NeighbourSectionHeader(title: "Mes livraisons en cours", systemImage: "figure.walk.motion",
                                       count: content.activeDeliveries.count)
                ForEach(content.activeDeliveries) { request in
                    DeliveryRouteCard(
                        request: request, address: content.addresses[request.id],
                        isPending: viewModel.pendingId == request.id,
                        startRoute: { Task { await viewModel.startRoute(request) } },
                        deliver: { Task { await viewModel.markDelivered(request) } },
                        release: { Task { await viewModel.release(request) } }
                    )
                    .grenierTransition(.cardAppear)
                }
            }

            NeighbourSectionHeader(title: "Voisins qui attendent", systemImage: "hand.raised.fill",
                                   count: content.openItems.count)
                .padding(.top, content.activeDeliveries.isEmpty ? 0 : 8)
            if content.openItems.isEmpty {
                DeliveryEmptyCard(
                    symbol: "checkmark.circle.fill", satellites: ["house.fill", "heart.fill"],
                    title: "Personne n'attend",
                    message: "Aucun voisin n'a besoin d'une livraison pour l'instant. Merci d'être là !",
                    actionTitle: "Actualiser", actionSymbol: "arrow.clockwise"
                ) {
                    Task { await viewModel.load() }
                }
            } else {
                if !content.canTakeMore {
                    NeighbourInfoLabel(
                        text: "Tu as déjà \(VolunteerDelivery.maxActivePerVolunteer) livraisons en cours : termine-en une d'abord.",
                        systemImage: "exclamationmark.circle.fill", font: .footnote
                    )
                }
                ForEach(Array(content.openItems.enumerated()), id: \.element.id) { index, item in
                    DeliveryOpenCard(
                        item: item, canClaim: content.canTakeMore && !viewModel.isBusy,
                        isPending: viewModel.pendingId == item.id
                    ) {
                        Task { await viewModel.claim(item.request) }
                    }
                    .grenierAppear(index: index)
                }
            }
        }
    }
}

private struct DeliveryVolunteerStats: View {
    let content: VolunteerDeliveryViewModel.Content

    var body: some View {
        HStack(spacing: 12) {
            tile(value: content.openItems.count, label: "à livrer", symbol: "hand.raised.fill", tint: .grenier)
            tile(value: content.activeDeliveries.count, label: "en cours", symbol: "figure.walk.motion", tint: .solidarite)
            tile(value: content.completedDeliveries.count, label: "livrées", symbol: "heart.fill", tint: .economie)
        }
    }

    private func tile(value: Int, label: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
            Text("\(value)")
                .font(.title2.bold())
                .fontDesign(.rounded)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.texte)
            Text(label).font(.caption).foregroundStyle(.texteSecondaire)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard(padding: 12)
        .accessibilityElement(children: .combine)
    }
}

/// Demande ouverte : voisin, motif, distance, créneau, parts, mot, « Je livre ».
private struct DeliveryOpenCard: View {
    let item: VolunteerDeliveryViewModel.OpenItem
    let canClaim: Bool
    let isPending: Bool
    let claim: () -> Void

    @State private var taps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var request: VolunteerDelivery.Request { item.request }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                NeighbourAvatar(name: request.householdName, tint: .solidarite)
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.householdName).font(.headline).foregroundStyle(.texte)
                    NeighbourBadge(text: request.reason.title, systemImage: request.reason.systemImage, tint: .solidarite)
                }
                Spacer(minLength: 8)
                if let distance = NeighbourHelpFormat.distance(item.distanceMeters) {
                    NeighbourBadge(text: distance, systemImage: "location.fill")
                }
            }
            NeighbourInfoLabel(text: NeighbourHelpFormat.window(start: request.window.start, end: request.window.end),
                               systemImage: "calendar.badge.clock")
            NeighbourInfoLabel(text: FrenchPlural.count(request.quantity, "part") + " à récupérer chez l'hôte",
                               systemImage: "square.stack.3d.up.fill")
            if let note = request.note {
                Label {
                    Text("« \(note) »").italic().foregroundStyle(.texte)
                } icon: {
                    Image(systemName: "quote.bubble.fill").symbolRenderingMode(.hierarchical).foregroundStyle(Color.solidarite)
                }
                .font(.subheadline)
            }
            Button {
                taps += 1
                claim()
            } label: {
                HStack {
                    if isPending { ProgressView() }
                    Label("Je livre", systemImage: "hand.wave.fill")
                        .symbolEffect(.bounce, value: reduceMotion ? 0 : taps)
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
            .tint(.grenier)
            .disabled(!canClaim)
            .accessibilityHint("Tu t'engages à apporter la part de \(request.householdName) pendant son créneau.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
        .contextMenu {
            Button("Je livre", systemImage: "hand.wave.fill", action: claim).disabled(!canClaim)
        }
    }
}

/// Livraison en cours du bénévole : adresse révélée, itinéraire, étape suivante.
private struct DeliveryRouteCard: View {
    let request: VolunteerDelivery.Request
    let address: VolunteerDelivery.PrivateAddress?
    let isPending: Bool
    let startRoute: () -> Void
    let deliver: () -> Void
    let release: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                NeighbourAvatar(name: request.householdName, tint: .solidarite)
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.householdName).font(.headline).foregroundStyle(.texte)
                    NeighbourBadge(text: request.status.title, systemImage: request.status.systemImage,
                                   tint: DeliveryStyle.tint(request.status))
                }
                Spacer(minLength: 0)
            }
            if let address {
                NeighbourInfoLabel(text: address.address, systemImage: "house.fill")
                if let instructions = address.instructions {
                    NeighbourInfoLabel(text: instructions, systemImage: "info.circle.fill")
                }
            }
            NeighbourInfoLabel(text: NeighbourHelpFormat.window(start: request.window.start, end: request.window.end),
                               systemImage: "calendar.badge.clock")
            NeighbourInfoLabel(text: FrenchPlural.count(request.quantity, "part"), systemImage: "square.stack.3d.up.fill")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { directions; nextStep }
                VStack(spacing: 8) { nextStep; directions }
            }
            if request.status == .claimed {
                Button("Je ne peux plus livrer", systemImage: "arrow.uturn.backward", role: .destructive, action: release)
                    .font(.footnote)
                    .disabled(isPending)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
    }

    @ViewBuilder private var directions: some View {
        if let url = address.flatMap({ NeighbourHelpFormat.walkingDirections(to: $0.address) }) {
            Button { openURL(url) } label: {
                Label("Itinéraire", systemImage: "map.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
            .tint(.grenier)
        }
    }

    @ViewBuilder private var nextStep: some View {
        Button(action: request.status == .claimed ? startRoute : deliver) {
            HStack {
                if isPending { ProgressView() }
                Label(request.status == .claimed ? "Part récupérée" : "Livrée !",
                      systemImage: request.status == .claimed ? "shippingbox.and.arrow.backward.fill" : "checkmark.circle.fill")
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .tint(request.status == .claimed ? .grenier : .economie)
        .disabled(isPending)
        .accessibilityHint(request.status == .claimed
            ? "À toucher quand l'hôte t'a remis la part."
            : "À toucher quand la part est remise au voisin.")
    }
}

// MARK: - Communs

private struct DeliveryEmptyCard: View {
    let symbol: String
    var satellites: [String] = []
    let title: String
    let message: String
    let actionTitle: String
    let actionSymbol: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            PickupSymbolScene(main: symbol, satellites: satellites, diameter: 72)
            Text(title).font(.title3.bold()).foregroundStyle(.texte)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .multilineTextAlignment(.center)
            Button(action: action) {
                Label(actionTitle, systemImage: actionSymbol)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.glass)
            .tint(.grenier)
        }
        .frame(maxWidth: .infinity)
        .grenierCard(padding: 20)
    }
}

private struct DeliveryErrorBanner: View {
    let error: AppError
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: error.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
            Text(error.message).font(.subheadline).foregroundStyle(.texte)
            Spacer(minLength: 0)
            Button("Fermer", systemImage: "xmark.circle.fill", action: dismiss)
                .labelStyle(.iconOnly)
                .foregroundStyle(.texteSecondaire)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.leading, 12)
        .background(Color.grenier.opacity(0.1), in: .rect(cornerRadius: 16))
    }
}

enum DeliveryStyle {
    static func tint(_ status: VolunteerDelivery.Status) -> Color {
        switch status {
        case .requested: .grenier
        case .claimed, .onTheWay: .solidarite
        case .delivered: .economie
        case .cancelled: .texteSecondaire
        }
    }
}

// MARK: - Previews

#Preview("Bénévole") {
    NavigationStack {
        VolunteerDeliveryScreen(viewModel: VolunteerDeliveryViewModel(
            repositories: AppContext.instant.repositories, userId: FakeData.ID.amina,
            householdId: FakeData.ID.aminaHousehold, groupId: FakeData.ID.saintMichel, mode: .volunteer
        ))
    }
}

#Preview("Ménage aîné") {
    NavigationStack {
        VolunteerDeliveryScreen(viewModel: VolunteerDeliveryViewModel(
            repositories: AppContext.instant.repositories, userId: "user-inconnu",
            householdId: "household-voisin-4", groupId: FakeData.ID.saintMichel
        ))
    }
    .preferredColorScheme(.dark)
}
