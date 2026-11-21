import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// F5 Cueillette (maquette `docs/maquettes/F5-cueillette.png`) : QR de la commande, point de cueillette, créneau et articles.
/// Branché sur `PickupViewModel` ; la luminosité passe au maximum tant que l'écran est affiché pour faciliter le scan.
/// Chaque en-tête, ligne, statut et chiffre clé porte son SF Symbol (rendu hiérarchique, teinte de la section) ;
/// l'en-tête et les états vides et de succès ont leur petite scène de symboles (`PickupSymbolScene`).
struct PickupScreen: View {
    @Environment(\.appContext) private var context
    @State private var viewModel: PickupViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    if case .empty = viewModel.state {
                        PickupIllustratedEmptyView(
                            title: "Aucune cueillette prévue",
                            message: "Réserve ta part d'un lot : ton code QR et ton créneau apparaîtront ici.",
                            main: GrenierSymbol.qrCode,
                            satellites: ["basket.fill", "calendar.badge.clock", "mappin.and.ellipse"],
                            action: .browseOffers
                        )
                    } else {
                        StateView(state: viewModel.state, retry: { await viewModel.load() }) { content in
                            PickupContentView(content: content)
                                .refreshable { await viewModel.load() }
                        }
                    }
                } else if context.isResolved && !context.hasGroup {
                    PickupIllustratedEmptyView(
                        title: "Aucune cueillette prévue",
                        message: "Rejoins un groupe de ton quartier pour réserver ta première part.",
                        main: GrenierSymbol.groups,
                        satellites: ["house.fill", "basket.fill", GrenierSymbol.solidarity],
                        action: .findGroup
                    )
                } else {
                    LoadingStateView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .grenierBackground()
            .navigationTitle("Cueillette")
            .profileToolbar()
            .pickupTools(groupOrderId: viewModel?.state.value?.items.first?.groupOrderId)
            // Retour sur l'onglet (ou depuis une fiche) : une part réservée entre-temps apparaît sans tirer pour actualiser.
            .onAppear { reloadIfAlreadyLoaded() }
        }
        .task(id: context.groupId) {
            guard viewModel == nil, context.hasGroup, let groupId = context.groupId else { return }
            let model = PickupViewModel(repositories: context.repositories, householdId: context.householdId, groupId: groupId)
            viewModel = model
            await model.load()
        }
    }

    /// Recharge seulement après un premier chargement : la `.task` s'occupe du tout premier.
    private func reloadIfAlreadyLoaded() {
        guard let viewModel else { return }
        switch viewModel.state {
        case .loaded, .empty: break
        case .idle, .loading, .failed: return
        }
        Task { await viewModel.load() }
    }
}

// MARK: - États illustrés

/// État vide avec une scène de symboles au lieu d'une icône seule.
private struct PickupIllustratedEmptyView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let main: String
    var satellites: [String] = []
    /// Prochaine étape proposée (rejoindre un groupe, voir les lots).
    var action: FamilyCallToAction.Destination?
    @ScaledMetric(relativeTo: .largeTitle) private var diameter: CGFloat = 110

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 16) {
                PickupSymbolScene(main: main, satellites: satellites, diameter: min(diameter, 160))
                Text(title).font(.title2.bold()).foregroundStyle(.texte)
            }
        } description: {
            Text(message)
        } actions: {
            if let action {
                FamilyCallToAction(destination: action)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
    }
}

// MARK: - Contenu

private struct PickupContentView: View {
    let content: PickupViewModel.Content

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var brightness = MaxBrightness()
    @State private var directionsTaps = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PickupHeroCard(content: content)
                if content.isAllPickedUp {
                    PickupAllDoneCard(hostFirstName: content.hostFirstName)
                }
                PickupCodeCard(content: content)
                PickupItemsCard(items: content.items)
                PickupPointSummaryCard(content: content)
                PickupNeighbourHelpCard(pickupPoint: content.pickupPoint, slot: content.slot) // RQ-069, RQ-070
                directionsButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .grenierScrollEdge()
        .onAppear { brightness.raise() }
        .onDisappear { brightness.restore() }
    }

    private var directionsButton: some View {
        Button {
            directionsTaps += 1
            if let url = PickupFormat.mapsURL(for: content.pickupPoint) { openURL(url) }
        } label: {
            Label {
                Text("Itinéraire à pied")
            } icon: {
                Image(systemName: "figure.walk.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.bounce, value: reduceMotion ? 0 : directionsTaps)
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glass)
        .tint(.grenier)
        .accessibilityHint("Ouvre Plans avec l'itinéraire vers \(content.pickupPoint.name)")
    }
}

/// En-tête illustré façon Live Activity : scène de symboles, « Cueillette dans 25 min », hôte et créneau.
private struct PickupHeroCard: View {
    let content: PickupViewModel.Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var diameter: CGFloat = 78

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let minutes = content.minutesUntilPickup(from: timeline.date)
            let done = content.isAllPickedUp
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(spacing: 16))
            layout {
                PickupSymbolScene(
                    main: done ? "checkmark.seal.fill" : "qrcode.viewfinder",
                    satellites: ["basket.fill", "house.fill", "clock.fill"],
                    tint: done ? .economie : .grenier,
                    diameter: min(diameter, 120)
                )
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text(done ? "Cueillette terminée" : PickupFormat.countdown(minutes: minutes))
                            .font(.title3.bold())
                            .foregroundStyle(.texte)
                            .contentTransition(.numericText())
                    } icon: {
                        Image(systemName: PickupFormat.countdownSymbol(minutes: minutes, done: done))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(done ? Color.economie : Color.grenier)
                            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                            .symbolEffect(.pulse, options: .repeating,
                                          isActive: !reduceMotion && !done && (minutes ?? .max) < 60)
                    }
                    PickupInfoLabel(text: hostLine, systemImage: "house.fill")
                    if let slot = content.slot {
                        PickupInfoLabel(text: PickupFormat.slot(slot), systemImage: "calendar.badge.clock")
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
                        LinearGradient(colors: [(done ? Color.economie : Color.grenier).opacity(0.14), .clear],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var hostLine: String {
        if let host = content.hostFirstName {
            return "Chez \(host) · \(content.pickupPoint.address)"
        }
        return content.pickupPoint.address
    }
}

/// Succès : toutes les parts sont récupérées.
private struct PickupAllDoneCard: View {
    let hostFirstName: String?

    var body: some View {
        HStack(spacing: 16) {
            PickupSymbolScene(main: "checkmark.seal.fill", tint: .economie, diameter: 56)
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text("Tout est récupéré").font(.headline).foregroundStyle(.texte)
                } icon: {
                    Image(systemName: "party.popper.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.economie)
                }
                Text(hostFirstName.map { "Merci d'avoir cueilli chez \($0) !" } ?? "Merci, bonne cuisine !")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
        .accessibilityElement(children: .combine)
    }
}

/// Grande carte du QR : « Montre ce code à Amina », « Commande GRN-1234 · 2 articles ».
private struct PickupCodeCard: View {
    let content: PickupViewModel.Content
    @ScaledMetric(relativeTo: .largeTitle) private var qrSize: CGFloat = 220

    var body: some View {
        VStack(spacing: 14) {
            PickupSectionHeader(title: "Ton code de cueillette", systemImage: "qrcode.viewfinder")
                .frame(maxWidth: .infinity, alignment: .leading)
            PickupQRImage(payload: content.qrPayload)
                .frame(width: min(qrSize, 300), height: min(qrSize, 300))
                .padding(16)
                // Le QR reste noir sur blanc, même en sombre, pour que tous les lecteurs le scannent.
                .background(Color.white, in: .rect(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.piste))
                .accessibilityLabel("Code QR de la commande \(content.orderCode)")

            Label {
                Text(hostInstruction)
                    .font(.title3.bold())
                    .foregroundStyle(.texte)
                    .multilineTextAlignment(.center)
            } icon: {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { orderLabel; articlesLabel }
                VStack(spacing: 6) { orderLabel; articlesLabel }
            }
            PickupInfoLabel(text: "Luminosité au maximum pour le scan", systemImage: "sun.max.fill", font: .caption)
        }
        .frame(maxWidth: .infinity)
        .grenierCard(padding: 20)
    }

    private var orderLabel: some View {
        PickupInfoLabel(text: "Commande \(content.orderCode)", systemImage: "number.circle.fill")
            .monospacedDigit()
            .textSelection(.enabled)
    }

    private var articlesLabel: some View {
        PickupInfoLabel(text: articles, systemImage: "shippingbox.fill")
    }

    private var hostInstruction: String {
        content.hostFirstName.map { "Montre ce code à \($0)" } ?? "Montre ce code à ton hôte"
    }

    private var articles: String {
        content.items.count == 1 ? "1 article" : "\(content.items.count) articles"
    }
}

/// Liste des articles à récupérer, chacun avec son statut (« Prêt à récupérer » / « Récupéré »).
private struct PickupItemsCard: View {
    let items: [PickupViewModel.Item]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 44

    private var pickedUpCount: Int { items.filter(\.isPickedUp).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack { header; Spacer(minLength: 8); progress }
                VStack(alignment: .leading, spacing: 6) { header; progress }
            }
            .padding(.bottom, 6)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().overlay(Color.piste) }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { icon(item); name(item); Spacer(minLength: 8); trailing(item, alignment: .trailing) }
                    VStack(alignment: .leading, spacing: 8) { icon(item); name(item); trailing(item, alignment: .leading) }
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
        }
        .grenierCard(padding: 16)
    }

    private var header: some View {
        PickupSectionHeader(title: "À récupérer", systemImage: "basket.fill")
    }

    private var progress: some View {
        Label {
            Text("\(pickedUpCount) sur \(items.count)")
                .contentTransition(.numericText())
        } icon: {
            Image(systemName: pickedUpCount == items.count ? "checklist.checked" : "checklist")
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
        }
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(pickedUpCount == items.count ? Color.economie : Color.texteSecondaire)
        .accessibilityLabel("\(pickedUpCount) sur \(items.count) récupérés")
    }

    private func icon(_ item: PickupViewModel.Item) -> some View {
        Image(systemName: item.product.category == .produce ? ProductIcon.symbol(for: item.product) : PickupFormat.symbol(for: item.product.category))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(item.isPickedUp ? Color.economie : Color.grenier)
            .frame(width: iconSize, height: iconSize)
            .background((item.isPickedUp ? Color.economie : Color.grenier).opacity(0.12), in: .rect(cornerRadius: 14))
            .accessibilityHidden(true)
    }

    private func name(_ item: PickupViewModel.Item) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.product.name).font(.body).foregroundStyle(.texte)
            PickupInfoLabel(text: Money.format(item.totalCents), systemImage: "dollarsign.circle.fill")
                .monospacedDigit()
        }
    }

    private func trailing(_ item: PickupViewModel.Item, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Label {
                Text("\(item.quantity) × \(item.offer.shareUnit)")
            } icon: {
                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(Color.grenier)
            }
            .font(.headline)
            .foregroundStyle(.texte)
            .monospacedDigit()
            .symbolRenderingMode(.hierarchical)
            statusBadge(item)
        }
    }

    private func statusBadge(_ item: PickupViewModel.Item) -> some View {
        let tint: Color = item.isPickedUp ? .economie : .grenier
        return Label {
            Text(item.isPickedUp ? "Récupéré" : "Prêt à récupérer")
        } icon: {
            Image(systemName: item.isPickedUp ? "checkmark.circle.fill" : "shippingbox.and.arrow.backward.fill")
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .symbolEffect(.bounce, value: reduceMotion ? false : item.isPickedUp)
        }
        .font(.caption.weight(.semibold))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: .capsule)
    }
}

/// Point de cueillette : nom, adresse, accessibilité et montant à payer.
private struct PickupPointSummaryCard: View {
    let content: PickupViewModel.Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PickupSectionHeader(title: "Point de cueillette", systemImage: "mappin.and.ellipse")
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(content.pickupPoint.name).font(.headline).foregroundStyle(.texte)
                    Text(content.pickupPoint.address).font(.subheadline).foregroundStyle(.texteSecondaire)
                }
            } icon: {
                Image(systemName: "house.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
            }
            if !content.pickupPoint.accessibility.isEmpty {
                PickupAccessibilityTags(items: content.pickupPoint.accessibility)
            }
            Divider().overlay(Color.piste)
            HStack {
                Label {
                    Text("À payer à la cueillette").font(.subheadline).foregroundStyle(.texteSecondaire)
                } icon: {
                    Image(systemName: "banknote.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.grenier)
                }
                Spacer(minLength: 8)
                Text(Money.format(content.totalCents)).priceStyle(.priceCompact).foregroundStyle(.texte)
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
    }
}

/// Pastilles d'accessibilité du point (« Accessible en fauteuil », « Près du métro »…), chacune avec son symbole.
private struct PickupAccessibilityTags: View {
    let items: [PickupPoint.Accessibility]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { tags }
            VStack(alignment: .leading, spacing: 6) { tags }
        }
    }

    private var tags: some View {
        ForEach(items, id: \.self) { item in
            Label(PickupFormat.title(for: item), systemImage: PickupFormat.symbol(for: item))
                .font(.caption.weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.texteSecondaire)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.piste.opacity(0.5), in: .capsule)
        }
    }
}

// MARK: - Petits éléments

/// En-tête de section : symbole teinté + titre.
private struct PickupSectionHeader: View {
    let title: LocalizedStringKey
    let systemImage: String
    var tint: Color = .grenier

    var body: some View {
        Label {
            Text(title).font(.headline).foregroundStyle(.texte)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// Info secondaire : symbole teinté + texte gris.
private struct PickupInfoLabel: View {
    let text: String
    let systemImage: String
    var font: Font = .subheadline

    var body: some View {
        Label {
            Text(text).foregroundStyle(.texteSecondaire)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
        }
        .font(font)
    }
}

private extension PickupViewModel.Content {
    /// Toutes les parts sont récupérées : état de succès.
    var isAllPickedUp: Bool { !items.isEmpty && items.allSatisfy(\.isPickedUp) }
}

// MARK: - QR

/// QR code net (pixels non lissés), généré par Core Image.
private struct PickupQRImage: View {
    let payload: String

    var body: some View {
        if let image = Self.makeImage(payload) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: GrenierSymbol.qrCode)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.texte)
        }
    }

    static func makeImage(_ payload: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}

// MARK: - Luminosité

/// Monte la luminosité au maximum à l'apparition et la remet à sa valeur précédente au départ.
@MainActor
private struct MaxBrightness {
    private var previous: CGFloat?

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?.screen
    }

    mutating func raise() {
        guard previous == nil, let screen else { return }
        previous = screen.brightness
        screen.brightness = 1
    }

    mutating func restore() {
        guard let previous, let screen else { return }
        screen.brightness = previous
        self.previous = nil
    }
}

// MARK: - Formatage

private enum PickupFormat {
    private static let locale = Locale(identifier: "fr_CA")

    /// « Cueillette dans 25 min », « Cueillette dans 3 h », « Cueillette dans 2 jours ».
    static func countdown(minutes: Int?) -> String {
        guard let minutes else { return "Créneau à confirmer" }
        switch minutes {
        case 0: return "C'est l'heure de ta cueillette"
        case ..<60: return "Cueillette dans \(minutes) min"
        case ..<(24 * 60): return "Cueillette dans \(minutes / 60) h"
        default:
            let days = minutes / (24 * 60)
            return days == 1 ? "Cueillette demain" : "Cueillette dans \(days) jours"
        }
    }

    /// « Jeudi 27 novembre · 17 h – 18 h 30 »
    static func slot(_ slot: PickupSlot) -> String {
        let day = slot.start.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
        return "\(day.prefix(1).uppercased())\(day.dropFirst()) · \(hour(slot.start)) – \(hour(slot.end))"
    }

    /// « 17 h » ou « 18 h 30 ».
    static func hour(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0
        return minute == 0 ? "\(hour) h" : "\(hour) h \(String(format: "%02d", minute))"
    }

    static func mapsURL(for point: PickupPoint) -> URL? {
        var components = URLComponents(string: "maps://")
        components?.queryItems = [URLQueryItem(name: "daddr", value: point.address), URLQueryItem(name: "dirflg", value: "w")]
        return components?.url
    }

    /// Symbole du compte à rebours : réveil quand c'est l'heure, minuteur quand c'est proche, calendrier sinon.
    static func countdownSymbol(minutes: Int?, done: Bool) -> String {
        if done { return "checkmark.circle.fill" }
        guard let minutes else { return "calendar.badge.exclamationmark" }
        switch minutes {
        case 0: return "bell.badge.fill"
        case ..<60: return "timer"
        case ..<(24 * 60): return "clock.fill"
        default: return "calendar"
        }
    }

    static func symbol(for accessibility: PickupPoint.Accessibility) -> String {
        switch accessibility {
        case .wheelchair: "figure.roll"
        case .stepFree: "figure.walk"
        case .elevator: "arrow.up.arrow.down.square.fill"
        case .nearMetro: "tram.fill"
        case .parking: "parkingsign.circle.fill"
        }
    }

    static func symbol(for category: Product.Category) -> String {
        switch category {
        case .grains, .flour: "bag.fill"
        case .legumes: "circle.grid.3x3.fill"
        case .oils: "drop.fill"
        case .canned: "cylinder.fill"
        case .eggs: "egg.fill"
        case .meat: "fork.knife"
        case .produce: "basket.fill"
        case .household: "sparkles"
        }
    }

    static func title(for accessibility: PickupPoint.Accessibility) -> String {
        switch accessibility {
        case .wheelchair: "Accessible en fauteuil"
        case .stepFree: "Sans marche"
        case .elevator: "Ascenseur"
        case .nearMetro: "Près du métro"
        case .parking: "Stationnement"
        }
    }
}

// MARK: - Previews

/// Réserve la part d'Amina avant d'afficher l'écran, pour voir le QR et les articles.
private struct PickupPreviewHost: View {
    @State private var isReady = false

    var body: some View {
        if isReady {
            PickupScreen()
        } else {
            ProgressView().task {
                _ = try? await AppContext.instant.repositories.groupOrders.setShare(
                    quantity: 2, householdId: FakeData.ID.aminaHousehold, groupOrderId: FakeData.ID.potatoOrder
                )
                isReady = true
            }
        }
    }
}

#Preview("Clair") {
    PickupPreviewHost()
        .environment(\.appContext, .instant)
}

#Preview("Sombre") {
    PickupPreviewHost()
        .environment(\.appContext, .instant)
        .preferredColorScheme(.dark)
}

#Preview("Vide") {
    PickupScreen()
        .environment(\.appContext, AppContext(
            repositories: .fake(behavior: .instant), userId: FakeData.ID.amina,
            householdId: "household-sans-part", groupId: FakeData.ID.saintMichel, vendorId: FakeData.ID.moulinsDuNord
        ))
}
