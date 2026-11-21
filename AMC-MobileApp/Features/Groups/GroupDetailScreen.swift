import MapKit
import SwiftUI

/// F2 Fiche d'un groupe de quartier (maquette `docs/maquettes/F2-groupe.png`) :
/// carte du quartier, nom, membres, point et horaire de cueillette, lots ouverts, invitation, Rejoindre.
/// Poussée dans le NavigationStack de l'onglet Groupes (qui enregistre `.offerDestination()`).
struct GroupDetailScreen: View {
    let groupId: String

    @Environment(\.appContext) private var context
    @State private var viewModel: GroupDetailViewModel?

    var body: some View {
        Group {
            if let viewModel {
                StateView(state: viewModel.state, retry: { await viewModel.load() }) { content in
                    GroupDetailContent(content: content, viewModel: viewModel)
                }
            } else {
                ProgressView("Chargement…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .grenierBackground()
        .navigationTitle(viewModel?.state.value?.group.name ?? "Groupe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let group = viewModel?.state.value?.group {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: GroupInvite.message(for: group)) {
                        Label("Partager le groupe", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .refreshable { await viewModel?.load() }
        .alert(
            viewModel?.actionError?.title ?? "",
            isPresented: Binding(
                get: { viewModel?.actionError != nil },
                set: { if !$0 { viewModel?.actionError = nil } }
            ),
            presenting: viewModel?.actionError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
        .task(id: groupId) {
            guard viewModel == nil else { return }
            let model = GroupDetailViewModel(
                repositories: context.repositories,
                householdId: context.householdId,
                groupId: groupId
            )
            viewModel = model
            await model.load()
        }
    }
}

// MARK: - Contenu

private struct GroupDetailContent: View {
    let content: GroupDetailViewModel.Content
    let viewModel: GroupDetailViewModel

    @State private var isConfirmingLeave = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var group: NeighborhoodGroup { content.group }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GroupMapHeader(group: group, hasPickupPoint: content.pickupPoint != nil)

                header

                PickupCard(pickupPoint: content.pickupPoint, slot: content.nextSlot)

                openOrdersSection

                InvitationCard(group: group)

                if content.isMember {
                    Button(role: .destructive) {
                        isConfirmingLeave = true
                    } label: {
                        Label("Quitter le groupe", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .disabled(viewModel.isUpdatingMembership)
                    .confirmationDialog("Quitter \(group.name) ?", isPresented: $isConfirmingLeave, titleVisibility: .visible) {
                        Button("Quitter le groupe", role: .destructive) {
                            Task { await viewModel.leave() }
                        }
                        Button("Annuler", role: .cancel) {}
                    } message: {
                        Text("Tes parts déjà réservées restent valides. Tu pourras revenir quand tu veux.")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .safeAreaInset(edge: .bottom) {
            if !content.isMember {
                Button {
                    Task { await viewModel.join() }
                } label: {
                    Group {
                        if viewModel.isUpdatingMembership {
                            ProgressView()
                        } else {
                            Label("Rejoindre le groupe", systemImage: "plus")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.grenier)
                .controlSize(.large)
                .disabled(viewModel.isUpdatingMembership)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: content.isMember)
        .sensoryFeedback(.success, trigger: content.isMember)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Groupe de quartier · \(group.neighborhood)".uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.grenier)
            Text(group.name)
                .font(.largeTitle.bold())
                .foregroundStyle(.texte)
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { members }
                VStack(alignment: .leading, spacing: 8) { members }
            }
        }
    }

    @ViewBuilder
    private var members: some View {
        let initials = content.members.prefix(3).map { MemberInitials.of($0.householdId) }
        AvatarStack(initials: initials, extraCount: max(group.householdCount - initials.count, 0))
        VStack(alignment: .leading, spacing: 2) {
            Text("\(group.householdCount) \(group.householdCount > 1 ? "familles" : "famille")")
                .font(.body)
                .foregroundStyle(.texteSecondaire)
            if content.isMember {
                Label("Tu en fais partie", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.economie)
                    .symbolEffect(.bounce, value: content.isMember)
            }
        }
    }

    @ViewBuilder
    private var openOrdersSection: some View {
        let orders = content.openOrders
        VStack(alignment: .leading, spacing: 12) {
            Text(orders.isEmpty ? "Aucun lot ouvert"
                 : "\(orders.count) \(orders.count > 1 ? "lots ouverts" : "lot ouvert")")
                .font(.title3.bold())
                .foregroundStyle(.texte)
                .accessibilityAddTraits(.isHeader)
            if orders.isEmpty {
                Text("Le groupe n'a pas de commande en cours. Les nouveaux lots du quartier apparaîtront ici.")
                    .font(.body)
                    .foregroundStyle(.texteSecondaire)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .grenierCard()
            } else {
                ForEach(orders) { summary in
                    NavigationLink(value: OfferRoute(offerId: summary.offer.id)) {
                        OfferCard(
                            offer: summary.offer,
                            product: summary.product,
                            vendor: summary.vendor,
                            committedShares: summary.committedShares,
                            committedHouseholds: summary.committedHouseholds
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Ouvre la fiche du lot.")
                }
            }
        }
    }
}

// MARK: - Carte du quartier

/// Carte MapKit centrée sur la zone du groupe (cercle) et le point de cueillette.
private struct GroupMapHeader: View {
    let group: NeighborhoodGroup
    let hasPickupPoint: Bool

    @ScaledMetric(relativeTo: .title) private var height: CGFloat = 240

    var body: some View {
        let center = Geohash.center(of: group.centerGeohash)
        let span = Double(group.radiusMeters) * 3
        Map(initialPosition: .region(MKCoordinateRegion(center: center, latitudinalMeters: span, longitudinalMeters: span)),
            interactionModes: []) {
            MapCircle(center: center, radius: CLLocationDistance(group.radiusMeters))
                .foregroundStyle(Color.grenier.opacity(0.12))
                .stroke(Color.grenier.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            if hasPickupPoint {
                Annotation("Point de cueillette", coordinate: center) {
                    Image(systemName: GrenierSymbol.offers)
                        .font(.headline)
                        .foregroundStyle(Color.onAccent)
                        .padding(10)
                        .background(Color.grenier, in: .rect(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.surface, lineWidth: 3))
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: min(height, 360))
        .clipShape(.rect(cornerRadius: 24))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Carte du quartier \(group.neighborhood), rayon de \(GroupCard.distanceText(group.radiusMeters))")
    }
}

// MARK: - Cueillette

private struct PickupCard: View {
    let pickupPoint: PickupPoint?
    let slot: PickupSlot?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            row(symbol: "mappin.and.ellipse", tint: .economie,
                title: pickupPoint?.name ?? "Point de cueillette à venir",
                subtitle: pickupPoint.map { "Point de cueillette · \($0.address)" }
                    ?? "L'hôte sera choisi à la prochaine commande")
            Divider().overlay(Color.piste)
            row(symbol: "clock", tint: .grenier,
                title: slot.map(PickupTime.text(for:)) ?? "Horaire à venir",
                subtitle: slot == nil ? "Annoncé dès qu'une commande est lancée" : "Prochaine cueillette")
        }
        .grenierCard()
    }

    private func row(symbol: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.texte)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Invitation

private struct InvitationCard: View {
    let group: NeighborhoodGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Invite tes voisins", systemImage: "person.badge.plus")
                .font(.headline)
                .foregroundStyle(.texte)
                .symbolRenderingMode(.hierarchical)
            Text("Plus vous êtes nombreux, plus le prix baisse. Partage le code du groupe :")
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
            ViewThatFits(in: .horizontal) {
                HStack { code; Spacer(minLength: 8); share }
                VStack(alignment: .leading, spacing: 12) { code; share }
            }
        }
        .grenierCard()
    }

    private var code: some View {
        Text(group.inviteCode)
            .font(.title3.bold())
            .fontDesign(.monospaced)
            .foregroundStyle(Color.grenier)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.grenier.opacity(0.12), in: .capsule)
            .textSelection(.enabled)
            .accessibilityLabel("Code d'invitation \(group.inviteCode.map(String.init).joined(separator: " "))")
    }

    private var share: some View {
        ShareLink(item: GroupInvite.message(for: group)) {
            Label("Inviter", systemImage: "square.and.arrow.up")
                .fontWeight(.semibold)
        }
        .buttonStyle(.glass)
        .tint(.grenier)
    }
}

// MARK: - Aides de présentation

private enum GroupInvite {
    static func message(for group: NeighborhoodGroup) -> String {
        "Rejoins « \(group.name) » sur Grenier pour acheter en gros avec tes voisins de \(group.neighborhood). Code : \(group.inviteCode)"
    }
}

private enum MemberInitials {
    /// « household-voisin-3 » → « V3 », « household-benali » → « B ».
    static func of(_ householdId: String) -> String {
        let parts = householdId.split(separator: "-").dropFirst()
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

enum PickupTime {
    private static let locale = Locale(identifier: "fr_CA")

    /// « Jeudi, 17 h – 18 h 30 »
    static func text(for slot: PickupSlot) -> String {
        let day = slot.start.formatted(.dateTime.weekday(.wide).locale(locale))
        return "\(day.prefix(1).uppercased())\(day.dropFirst()), \(hour(slot.start)) – \(hour(slot.end))"
    }

    /// « 17 h » ou « 18 h 30 »
    static func hour(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0
        return minute == 0 ? "\(hour) h" : String(format: "%d h %02d", hour, minute)
    }
}

/// Décodage d'un geohash vers le centre de sa cellule (pour placer la carte du groupe).
enum Geohash {
    private static let alphabet = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    static func center(of hash: String) -> CLLocationCoordinate2D {
        var latitude = (-90.0, 90.0), longitude = (-180.0, 180.0)
        var isLongitude = true
        for character in hash.lowercased() {
            guard let value = alphabet.firstIndex(of: character) else { break }
            for bit in (0..<5).reversed() {
                let isSet = (value >> bit) & 1 == 1
                if isLongitude {
                    let mid = (longitude.0 + longitude.1) / 2
                    if isSet { longitude.0 = mid } else { longitude.1 = mid }
                } else {
                    let mid = (latitude.0 + latitude.1) / 2
                    if isSet { latitude.0 = mid } else { latitude.1 = mid }
                }
                isLongitude.toggle()
            }
        }
        return CLLocationCoordinate2D(latitude: (latitude.0 + latitude.1) / 2,
                                      longitude: (longitude.0 + longitude.1) / 2)
    }
}

#Preview("Clair — membre") {
    NavigationStack {
        GroupDetailScreen(groupId: FakeData.ID.saintMichel)
            .offerDestination()
    }
    .environment(\.appContext, .instant)
}

#Preview("Sombre — pas membre") {
    NavigationStack {
        GroupDetailScreen(groupId: FakeData.ID.hochelaga)
            .offerDestination()
    }
    .environment(\.appContext, .instant)
    .preferredColorScheme(.dark)
}
