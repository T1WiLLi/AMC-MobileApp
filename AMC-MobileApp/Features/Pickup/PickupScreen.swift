import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// F5 Cueillette (maquette `docs/maquettes/F5-cueillette.png`) : QR de la commande, point de cueillette, créneau et articles.
/// Branché sur `PickupViewModel` ; la luminosité passe au maximum tant que l'écran est affiché pour faciliter le scan.
/// Chaque en-tête, ligne, statut et chiffre clé porte son SF Symbol (rendu hiérarchique, teinte de la section) ;
/// les états vides et de succès ont leur petite scène de symboles (`PickupSymbolScene`).
struct PickupScreen: View {
    @Environment(\.appContext) private var context
    @State private var viewModel: PickupViewModel?
    /// Groupe du modèle courant : un autre groupe actif recrée le modèle.
    @State private var loadedGroupId: String?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    if case .empty = viewModel.state {
                        PickupIllustratedEmptyView(
                            title: "Aucune cueillette prévue",
                            message: "Ici, tu trouveras ton code QR, ton point et ton créneau pour récupérer tes parts. Réserve ta part d'un lot pour commencer.",
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
        .task(id: modelKey) {
            // Nouveau groupe actif ou nouveau ménage (rejoint) : nouveau modèle, sinon on garderait les parts de l'ancien.
            guard context.hasGroup, context.groupId != nil else { viewModel = nil; loadedGroupId = nil; return }
            guard let groupId = context.groupId, viewModel == nil || loadedGroupId != modelKey else { return }
            loadedGroupId = modelKey
            let model = PickupViewModel(repositories: context.repositories, householdId: context.householdId, groupId: groupId,
                                        userId: context.userId)
            viewModel = model
            await model.load()
        }
    }

    /// Ménage et groupe actif du modèle courant.
    private var modelKey: String { "\(context.householdId)|\(context.groupId ?? "")" }

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

/// T-198 : plusieurs groupes : un sélecteur en haut choisit le groupe, et l'écran ne montre que lui (SON QR, ses
/// lieux, ses articles, son créneau et son total).
private struct PickupContentView: View {
    let allContent: PickupViewModel.Content

    init(content: PickupViewModel.Content) {
        allContent = content
    }

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var brightness = MaxBrightness()
    @State private var directionsTaps = 0
    /// Groupe choisi dans le sélecteur ; le premier (groupe actif) par défaut.
    @State private var selectedGroupId: String?

    /// Le contenu du groupe choisi.
    private var content: PickupViewModel.Content { allContent.scoped(to: selectedGroupId) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if allContent.groups.count > 1 {
                    PickupGroupPicker(groups: allContent.groups,
                                      selection: Binding(get: { content.groups.first?.id ?? "" },
                                                         set: { selectedGroupId = $0 }))
                }
                PickupHeroCard(content: content)
                // La livraison : en route (commande fermée) ou arrivée chez l'hôte (on peut venir la chercher).
                if let arrival = content.arrival {
                    PickupArrivalBanner(arrival: arrival)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if content.isAllPickedUp {
                    PickupAllDoneCard(hostFirstName: content.hostFirstName)
                }
                if let group = content.groups.first {
                    PickupCodeCard(group: group)
                        .guidedTourAnchor(.pickup)
                }
                // Une section par lieu : ses articles, son point (ou « Lieu à confirmer ») et son montant.
                ForEach(Array(content.places.enumerated()), id: \.element.id) { index, place in
                    placeSection(place, index: index)
                }
                PickupRateVendorsCard(items: content.items) // T-157 : noter le producteur après la cueillette
                if let point = content.pickupPoint {
                    PickupNeighbourHelpCard(pickupPoint: point, slot: content.slot) // RQ-069, RQ-070
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .animation(reduceMotion ? nil : .smooth, value: content)
        }
        .guidedTourScroll(.noisette)
        .grenierScrollEdge()
        .onAppear { brightness.raise() }
        .onDisappear { brightness.restore() }
    }

    @ViewBuilder
    private func placeSection(_ place: PickupViewModel.Place, index: Int) -> some View {
        let count = content.places.count
        if count > 1 {
            PickupPlaceHeading(place: place, number: index + 1, count: count)
                .padding(.top, index == 0 ? 4 : 12)
        }
        PickupItemsCard(items: place.items)
        if let point = place.pickupPoint {
            PickupPointSummaryCard(point: point, totalCents: place.totalCents)
            directionsButton(to: point)
        } else {
            // Lot réservé, mais le groupe n'a pas encore choisi où cueillir.
            PickupPointPendingCard(totalCents: place.totalCents)
        }
    }

    private func directionsButton(to point: PickupPoint) -> some View {
        Button {
            directionsTaps += 1
            if let url = PickupFormat.mapsURL(for: point) { openURL(url) }
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
        .accessibilityHint("Ouvre Plans avec l'itinéraire vers \(point.name)")
    }
}

/// En-tête façon Live Activity : « Cueillette dans 3 jours » sur toute la largeur, puis le lieu et le créneau
/// en lignes pleine largeur (le grand QR est juste en dessous, inutile de le répéter ici).
private struct PickupHeroCard: View {
    let content: PickupViewModel.Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var badgeSize: CGFloat = 40

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let minutes = content.minutesUntilPickup(from: timeline.date)
            let done = content.isAllPickedUp
            let tint: Color = done ? .economie : .grenier
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    // En très grand texte, la pastille et les icônes de ligne prendraient la moitié de la largeur.
                    if !dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: PickupFormat.countdownSymbol(minutes: minutes, done: done))
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(tint)
                            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                            .symbolEffect(.pulse, options: .repeating,
                                          isActive: !reduceMotion && !done && (minutes ?? .max) < 60)
                            .frame(width: min(badgeSize, 64), height: min(badgeSize, 64))
                            .background(tint.opacity(0.14), in: .circle)
                            .accessibilityHidden(true)
                    }
                    Text(done ? String(localized: "Cueillette terminée") : PickupFormat.countdown(minutes: minutes))
                        .font(.title2.bold())
                        .foregroundStyle(.texte)
                        .contentTransition(.numericText())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider().overlay(Color.piste)
                heroRow(hostLine, systemImage: "house.fill")
                if let slot = content.slot {
                    heroRow(PickupFormat.slot(slot), systemImage: "calendar.badge.clock")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 24).fill(Color.surface)
                    RoundedRectangle(cornerRadius: 24).fill(
                        LinearGradient(colors: [tint.opacity(0.14), .clear],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Ligne pleine largeur, icône alignée sur la première ligne du texte.
    private func heroRow(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text)
                .foregroundStyle(.texte)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
        }
        .labelStyle(HeroRowLabelStyle(showsIcon: !dynamicTypeSize.isAccessibilitySize))
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hostLine: String {
        // Plusieurs lieux : chacun a sa section plus bas.
        if content.places.count > 1 {
            return String(localized: "\(content.places.count) lieux de cueillette, détaillés plus bas")
        }
        guard let point = content.pickupPoint else { return String(localized: "Lieu à confirmer par ton groupe") }
        if let host = content.hostFirstName {
            return String(localized: "Chez \(host) · \(point.address)")
        }
        return point.address
    }
}

/// Icône + texte, ou texte seul en très grand texte (la ligne garde toute la largeur).
private struct HeroRowLabelStyle: LabelStyle {
    let showsIcon: Bool

    func makeBody(configuration: Configuration) -> some View {
        if showsIcon {
            Label(configuration)
        } else {
            configuration.title
        }
    }
}

/// État de la livraison : « En route — on te prévient dès l'arrivée » (commande fermée) ou
/// « Arrivée ! Viens la chercher », avec le lieu et le créneau (commande marquée arrivée par l'hôte ou la coordination).
private struct PickupArrivalBanner: View {
    let arrival: PickupViewModel.Arrival
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var badgeSize: CGFloat = 44

    private var isArrived: Bool {
        if case .arrived = arrival { true } else { false }
    }

    private var tint: Color { isArrived ? .economie : .grenier }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: isArrived ? "shippingbox.and.arrow.backward.fill" : "box.truck.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion && !isArrived)
                    .symbolEffect(.bounce, value: reduceMotion ? false : isArrived)
                    .frame(width: min(badgeSize, 64), height: min(badgeSize, 64))
                    .background(tint.opacity(0.16), in: .circle)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(isArrived ? String(localized: "Arrivée ! Viens la chercher") : String(localized: "En route"))
                    .font(.headline)
                    .foregroundStyle(.texte)
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(tint.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var lines: [String] {
        switch arrival {
        case .onTheWay:
            return [String(localized: "On te prévient dès l'arrivée chez l'hôte.")]
        case .arrived(let place):
            var lines: [String] = []
            if let point = place.pickupPoint { lines.append("\(point.name) · \(point.address)") }
            if let slot = place.slot { lines.append(PickupFormat.slot(slot)) }
            lines.append(String(localized: "Montre ton code QR à l'hôte."))
            return lines
        }
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
                Text(hostFirstName.map { String(localized: "Merci d'avoir cueilli chez \($0) !") } ?? String(localized: "Merci, bonne cuisine !"))
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

/// Sélecteur du lieu de cueillette : segments pour deux lieux, menu au-delà (ou en très grand texte).
/// Choix du groupe (T-198) : chaque groupe a son QR, ses lieux et ses articles.
private struct PickupGroupPicker: View {
    let groups: [PickupViewModel.GroupPickup]
    @Binding var selection: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PickupSectionHeader(title: "Quel groupe ?", systemImage: "person.3.fill")
            if groups.count == 2 && !dynamicTypeSize.isAccessibilitySize {
                Picker("Groupe", selection: $selection) {
                    ForEach(groups) { group in Text(group.title).tag(group.id) }
                }
                .pickerStyle(.segmented)
            } else {
                Menu {
                    Picker("Groupe", selection: $selection) {
                        ForEach(groups) { group in
                            Label(group.title, systemImage: "person.3.fill").tag(group.id)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.3.fill").symbolRenderingMode(.hierarchical)
                        Text(groups.first { $0.id == selection }?.title ?? "")
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.semibold))
                    }
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)
                .tint(.grenier)
            }
        }
        .grenierHaptic(.selection, trigger: selection)
    }
}

/// Carte du code du groupe choisi (T-198) : UN QR pour toutes ses commandes fermées (l'hôte le scanne une fois et
/// remet toutes les parts qu'il garde), avec la liste de ce qu'il couvre. Sans commande fermée, pas de faux QR :
/// « Ton code apparaîtra à la clôture ».
private struct PickupCodeCard: View {
    let group: PickupViewModel.GroupPickup
    @ScaledMetric(relativeTo: .largeTitle) private var qrSize: CGFloat = 220

    var body: some View {
        VStack(spacing: 14) {
            PickupSectionHeader(title: "Ton code de cueillette", systemImage: "qrcode.viewfinder", info: .pickup)
                .frame(maxWidth: .infinity, alignment: .leading)
            switch group.codeState {
            case .codes(let items, let waiting):
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
                if let payload = group.qrPayload {
                    PickupQRImage(payload: payload)
                        .frame(width: min(qrSize, 300), height: min(qrSize, 300))
                        .padding(16)
                        // Le QR reste noir sur blanc, même en sombre, pour que tous les lecteurs le scannent.
                        .background(Color.white, in: .rect(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.piste))
                        .accessibilityLabel("Code QR de cueillette du groupe \(group.title)")
                }
                PickupInfoLabel(text: group.title, systemImage: "person.3.fill")
                    .fontWeight(.semibold)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items) { item in
                        PickupInfoLabel(text: String(localized: "\(item.product.name) · \(item.quantity) × \(item.offer.displayShareUnit)"),
                                        systemImage: "basket.fill", font: .caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(items.count > 1 ? "Ce code couvre \(items.count) articles" : "Ce code couvre 1 article")
                if waiting > 0 {
                    PickupInfoLabel(text: waiting == 1 ? String(localized: "L'autre article s'ajoutera au code à sa clôture")
                                        : String(localized: "Les \(waiting) autres articles s'ajouteront au code à leur clôture"),
                                    systemImage: "clock.fill", font: .caption)
                }
                PickupInfoLabel(text: String(localized: "Luminosité au maximum pour le scan"), systemImage: "sun.max.fill", font: .caption)
            case .awaitingClosure:
                PickupCodePendingState()
            case .allPickedUp:
                PickupInfoLabel(text: String(localized: "Tout est récupéré pour ce groupe : plus de code à montrer."),
                                systemImage: "checkmark.seal.fill")
            }
        }
        .frame(maxWidth: .infinity)
        .grenierCard(padding: 20)
    }

    private var hostInstruction: String {
        group.hostFirstName.map { String(localized: "Montre ce code à \($0)") } ?? String(localized: "Montre ce code à l'hôte")
    }
}

/// Commande encore ouverte : le code n'existe pas encore.
private struct PickupCodePendingState: View {
    var body: some View {
        VStack(spacing: 10) {
            PickupSymbolScene(main: "qrcode", satellites: ["lock.fill", "clock.fill"], diameter: 72)
            Text("Ton code apparaîtra à la clôture")
                .font(.headline)
                .foregroundStyle(.texte)
                .multilineTextAlignment(.center)
            Text("Quand la commande ferme, ton code de cueillette s'affiche ici. On te prévient ensuite dès que la livraison arrive.")
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Liste des articles à récupérer, comme une liste de cases à cocher native : tuile du produit à gauche,
/// nom, format et prix au centre, statut (« Prêt à récupérer » / « Récupéré par … ») et coche à droite.
private struct PickupItemsCard: View {
    let items: [PickupViewModel.Item]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                row(item)
            }
        }
        .grenierCard(padding: 16)
    }

    private func row(_ item: PickupViewModel.Item) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // En très grand texte, la tuile mangerait la moitié de la largeur : le nom passe avant.
            if !dynamicTypeSize.isAccessibilitySize { icon(item) }
            details(item)
                .frame(maxWidth: .infinity, alignment: .leading)
            check(item)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
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
            .background((item.isPickedUp ? Color.economie : Color.grenier).opacity(0.12), in: .rect(cornerRadius: 12))
            .accessibilityHidden(true)
    }

    /// Nom, « 1 × sac de 4 kg · 14,79 $ », puis le statut en couleur.
    private func details(_ item: PickupViewModel.Item) -> some View {
        let format = String(localized: "\(item.quantity) × \(item.offer.displayShareUnit)")
        return VStack(alignment: .leading, spacing: 2) {
            Text(item.product.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(.texte)
                .strikethrough(item.isPickedUp, color: .texteSecondaire)
            Text(verbatim: "\(format) · \(Money.format(item.totalCents))")
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .monospacedDigit()
            Text(statusText(item))
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor(item))
                .padding(.top, 2)
        }
    }

    /// T-159 : la part du ménage n'est récupérée qu'une fois ; tous les membres voient qui l'a prise.
    private func statusText(_ item: PickupViewModel.Item) -> String {
        guard item.isPickedUp else {
            switch item.orderStatus {
            case .delivered: return String(localized: "Arrivée ! Viens la chercher")
            case .closed: return String(localized: "En route — on te prévient dès l'arrivée")
            case .open, .reached, .cancelled: return String(localized: "Commande en cours")
            }
        }
        if let name = item.pickedUpByName { return String(localized: "Récupéré par \(name)") }
        return String(localized: "Récupéré")
    }

    private func statusColor(_ item: PickupViewModel.Item) -> Color {
        if item.isPickedUp { return .economie }
        return item.isReadyToPickUp ? .grenier : .texteSecondaire
    }

    /// Coche de la liste : cercle vide tant que la part attend, coche verte une fois récupérée.
    private func check(_ item: PickupViewModel.Item) -> some View {
        Image(systemName: item.isPickedUp ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(item.isPickedUp ? Color.economie : Color.texteSecondaire.opacity(0.6))
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            .symbolEffect(.bounce, value: reduceMotion ? false : item.isPickedUp)
            .accessibilityHidden(true)
    }
}

/// Titre d'une section de lieu quand il y en a plusieurs : « Lieu 1 sur 2 », nom du lieu, compte des articles.
private struct PickupPlaceHeading: View {
    let place: PickupViewModel.Place
    let number: Int
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text("Lieu \(number) sur \(count)")
            } icon: {
                Image(systemName: place.pickupPoint == nil ? "clock.badge.questionmark.fill" : "mappin.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
            }
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(Color.texteSecondaire)
            Text(place.pickupPoint?.name ?? String(localized: "Lieu à confirmer"))
                .font(.title3.bold())
                .foregroundStyle(Color.texte)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Point de cueillette : nom, adresse, accessibilité et montant à payer à ce lieu.
private struct PickupPointSummaryCard: View {
    let point: PickupPoint
    let totalCents: Cents

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PickupSectionHeader(title: "Point de cueillette", systemImage: "mappin.and.ellipse")
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(point.name).font(.headline).foregroundStyle(.texte)
                    Text(point.address).font(.subheadline).foregroundStyle(.texteSecondaire)
                }
            } icon: {
                Image(systemName: "house.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
            }
            if !point.accessibility.isEmpty {
                PickupAccessibilityTags(items: point.accessibility)
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
                Text(Money.format(totalCents)).priceStyle(.priceCompact).foregroundStyle(.texte)
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
    }
}

/// Part réservée sans point de cueillette encore choisi par le groupe : on le dit, avec le montant à payer.
private struct PickupPointPendingCard: View {
    let totalCents: Cents

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PickupSectionHeader(title: "Point de cueillette", systemImage: "mappin.and.ellipse")
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lieu à confirmer").font(.headline).foregroundStyle(.texte)
                    Text("Ton groupe choisira bientôt où et quand cueillir. Tu recevras une notification.")
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "clock.badge.questionmark.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
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
                Text(Money.format(totalCents)).priceStyle(.priceCompact).foregroundStyle(.texte)
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
    /// Bouton « i » à côté du titre (FB-08).
    var info: InfoTopic?

    var body: some View {
        HStack(spacing: 2) {
            Label {
                Text(title).font(.headline).foregroundStyle(.texte)
            } icon: {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
            }
            .accessibilityAddTraits(.isHeader)
            if let info { InfoButton(topic: info) }
        }
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

/// Après la cueillette (T-157) : un lien par producteur dont une part est récupérée, vers sa page pour le noter.
private struct PickupRateVendorsCard: View {
    let items: [PickupViewModel.Item]

    var body: some View {
        let picked = Dictionary(grouping: items.filter(\.isPickedUp), by: \.offer.vendorId)
            .compactMap { vendorId, items in items.first.map { (vendorId: vendorId, item: $0) } }
            .sorted { $0.item.product.name < $1.item.product.name }
        if !picked.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Comment était ton lot ?", systemImage: "star.bubble.fill")
                    .font(.headline)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.texte)
                Text("Ta note aide les autres familles à choisir leurs producteurs.")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                ForEach(picked, id: \.vendorId) { entry in
                    NavigationLink {
                        PublicVendorScreen(vendorId: entry.vendorId)
                    } label: {
                        Label("Noter le producteur · \(entry.item.product.name)", systemImage: "star.leadinghalf.filled")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.glass)
                    .tint(.grenier)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .grenierCard()
        }
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
    private static var locale: Locale { AppLanguage.formattingLocale }

    /// « Cueillette dans 25 min », « Cueillette dans 3 h », « Cueillette dans 2 jours ».
    static func countdown(minutes: Int?) -> String {
        guard let minutes else { return String(localized: "Créneau à confirmer") }
        switch minutes {
        case 0: return String(localized: "C'est l'heure de ta cueillette")
        case ..<60: return String(localized: "Cueillette dans \(minutes) min")
        case ..<(24 * 60): return String(localized: "Cueillette dans \(minutes / 60) h")
        default:
            let days = minutes / (24 * 60)
            return days == 1 ? String(localized: "Cueillette demain") : String(localized: "Cueillette dans \(days) jours")
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
        return AppLanguage.clockText(hour: hour, minute: minute)
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
        case .wheelchair: String(localized: "Accessible en fauteuil")
        case .stepFree: String(localized: "Sans marche")
        case .elevator: String(localized: "Ascenseur")
        case .nearMetro: String(localized: "Près du métro")
        case .parking: String(localized: "Stationnement")
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
