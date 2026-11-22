import SwiftUI

/// T-181 : l'hôte remet les parts. Pour chaque commande (une « station ») : le produit, le producteur, le point,
/// le créneau et l'état de la livraison (« En route », « Arrivée — remise en cours », « Terminée »).
/// Tant que la livraison n'est pas arrivée, l'action principale est « Marquer comme arrivée » (les familles sont
/// prévenues dans leur app) et le scan est désactivé. Ensuite : familles « À servir » / « Servis », « Récupéré »
/// d'un tap ou scan du code QR de la famille.
/// Poussé depuis la Cueillette (`PickupToolsMenu`) pour un hôte ou un coordonnateur, et depuis la fiche du groupe
/// (coordonnateur).
struct HostPickupScreen: View {
    @State private var viewModel: HostPickupViewModel
    @State private var showsScanner = false

    init(viewModel: HostPickupViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        StateView(
            state: viewModel.state,
            empty: .init(title: "Rien à remettre", systemImage: "shippingbox",
                         message: "Quand une commande sera fermée pour ton point ou ton groupe, elle apparaîtra ici : tu pourras la marquer comme arrivée, puis remettre les parts."),
            retry: { await viewModel.load() }
        ) { _ in
            HostPickupContent(viewModel: viewModel, showsScanner: $showsScanner)
                .refreshable { await viewModel.load() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
        .navigationTitle("Remettre les parts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar {
            if viewModel.selectedStation?.isArrived == true {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsScanner = true } label: {
                        Label("Scanner un code", systemImage: "qrcode.viewfinder")
                    }
                }
            }
        }
        .modifier(HostSearchModifier(isOn: viewModel.showsSearch, text: $viewModel.searchText))
        .sheet(isPresented: $showsScanner) { HostScannerSheet(viewModel: viewModel) }
        .grenierHaptic(.success, trigger: viewModel.successes)
        .grenierHaptic(.success, trigger: viewModel.arrivals)
        .grenierHaptic(.warning, trigger: viewModel.rejections)
        .alert("Oups", isPresented: Binding(get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.dismissError() } }),
               presenting: viewModel.actionError) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
        .task { if viewModel.state.value == nil { await viewModel.load() } }
    }
}

/// Recherche d'une famille, seulement quand la liste est longue.
private struct HostSearchModifier: ViewModifier {
    let isOn: Bool
    @Binding var text: String

    func body(content: Content) -> some View {
        if isOn {
            content.searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always),
                               prompt: Text("Chercher une famille"))
        } else {
            content
        }
    }
}

// MARK: - Contenu

private struct HostPickupContent: View {
    @Bindable var viewModel: HostPickupViewModel
    @Binding var showsScanner: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let content = viewModel.state.value, content.stations.count > 1 {
                    HostStationPicker(stations: content.stations, selectedId: viewModel.selectedStation?.id) {
                        viewModel.selectOrder($0)
                    }
                }
                if let station = viewModel.selectedStation, let board = viewModel.board {
                    HostStationHeader(station: station)
                    if viewModel.arrivedOrderId == station.id {
                        HostArrivalNotice { viewModel.dismissArrivalNotice() }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if station.isArrived {
                        HostProgressTiles(board: board)
                        if let outcome = viewModel.outcome {
                            HostOutcomeBanner(outcome: outcome) { viewModel.dismissOutcome() }
                        }
                        if !board.isComplete { scanButton }
                    } else {
                        HostArrivalCard(station: station, isPending: viewModel.arrivingOrderId == station.id) {
                            Task { await viewModel.markArrived(orderId: station.id) }
                        }
                    }
                    if station.slots.count > 1 { slotFilter(station) }
                    HostBoardSections(viewModel: viewModel, station: station, board: board)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .animation(reduceMotion ? nil : .snappy, value: viewModel.outcome)
            .animation(reduceMotion ? nil : .smooth, value: viewModel.selectedStation)
            .animation(reduceMotion ? nil : .smooth, value: viewModel.arrivedOrderId)
        }
        .grenierScrollEdge()
    }

    private var scanButton: some View {
        Button { showsScanner = true } label: {
            Label("Scanner le code d'une famille", systemImage: "qrcode.viewfinder")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(.grenier)
    }

    private func slotFilter(_ station: HostPickupViewModel.Station) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: String(localized: "Tous les créneaux"), isOn: viewModel.selectedSlot == nil) {
                    viewModel.selectedSlot = nil
                }
                ForEach(station.slots, id: \.self) { slot in
                    chip(title: slot.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLanguage.formattingLocale)), isOn: viewModel.selectedSlot == slot) {
                        viewModel.selectedSlot = slot
                    }
                }
            }
        }
        .grenierHaptic(.selection, trigger: viewModel.selectedSlot)
    }

    private func chip(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: isOn ? "clock.fill" : "clock")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(isOn ? Color.grenier.opacity(0.18) : Color.surface, in: .capsule)
                .overlay(Capsule().stroke(isOn ? Color.grenier : Color.piste, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? Color.grenier : Color.texte)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Choix de la commande

/// Plusieurs commandes chez l'hôte : une pastille par commande, avec son état.
private struct HostStationPicker: View {
    let stations: [HostPickupViewModel.Station]
    let selectedId: String?
    let select: (String) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            // En très grand texte, les pastilles s'empilent (une ligne défilante couperait les noms).
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { chips }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { chips }
                }
            }
        }
        .grenierHaptic(.selection, trigger: selectedId)
    }

    private var chips: some View {
                ForEach(stations) { station in
                    let isOn = station.id == selectedId
                    let stage = HostStageStyle(station.stage)
                    Button { select(station.id) } label: {
                        Label {
                            Text(station.productName).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: stage.symbol).foregroundStyle(stage.tint)
                        }
                        .font(.subheadline.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(isOn ? stage.tint.opacity(0.16) : Color.surface, in: .capsule)
                        .overlay(Capsule().stroke(isOn ? stage.tint : Color.piste, lineWidth: isOn ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.texte)
                    .accessibilityLabel("\(station.productName), \(stage.title)")
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
    }
}

// MARK: - En-tête

/// Couleur, symbole et libellé de l'état d'une commande.
private struct HostStageStyle {
    let title: String
    let symbol: String
    let tint: Color

    init(_ stage: OrderArrival.Stage) {
        switch stage {
        case .enRoute:
            title = String(localized: "En route")
            symbol = "box.truck.fill"
            tint = .grenier
        case .handingOut:
            title = String(localized: "Arrivée — remise en cours")
            symbol = "shippingbox.and.arrow.backward.fill"
            tint = .economie
        case .finished:
            title = String(localized: "Terminée")
            symbol = "checkmark.seal.fill"
            tint = .economie
        }
    }
}

/// Produit et format, producteur, point (nom et adresse), créneau et état de la livraison.
private struct HostStationHeader: View {
    let station: HostPickupViewModel.Station
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var tileSide: CGFloat = 52

    var body: some View {
        let stage = HostStageStyle(station.stage)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "basket.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.grenier)
                        .grenierIconTile(.grenier, side: min(tileSide, 72), cornerRadius: 14)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.productName)
                        .font(.title3.bold())
                        .foregroundStyle(.texte)
                        .fixedSize(horizontal: false, vertical: true)
                    if let unit = station.unit {
                        Text(String(localized: "Part : \(unit)"))
                            .font(.subheadline)
                            .foregroundStyle(.texteSecondaire)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            statusPill(stage)
            Divider().overlay(Color.piste)
            if let vendor = station.vendorName {
                row(vendor, systemImage: "storefront.fill", label: String(localized: "Producteur"))
            }
            row(pointText, systemImage: "mappin.and.ellipse", label: String(localized: "Point de cueillette"))
            row(slotText, systemImage: "calendar.badge.clock", label: String(localized: "Créneau"))
            if let group = station.groupName {
                row(group, systemImage: "person.3.fill", label: String(localized: "Groupe"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard(padding: 16)
        .accessibilityElement(children: .combine)
    }

    private func statusPill(_ stage: HostStageStyle) -> some View {
        Label {
            Text(stage.title)
        } icon: {
            Image(systemName: stage.symbol)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion && station.stage == .enRoute)
        }
        .font(.subheadline.weight(.semibold))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(stage.tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(stage.tint.opacity(0.14), in: .capsule)
        .accessibilityLabel("État : \(stage.title)")
    }

    private func row(_ text: String, systemImage: String, label: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.texte)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("\(label) : \(text)")
    }

    private var pointText: String {
        guard let point = station.point else { return String(localized: "Point à choisir par le groupe") }
        return "\(point.name) · \(point.address)"
    }

    private var slotText: String {
        let slots = station.order.pickupSlots.sorted { $0.start < $1.start }
        guard let first = slots.first else { return String(localized: "Créneau à confirmer") }
        let text = HostFormat.slot(first)
        let others = slots.count - 1
        if others == 0 { return text }
        return others == 1 ? String(localized: "\(text) (+ 1 autre créneau)")
            : String(localized: "\(text) (+ \(others) autres créneaux)")
    }
}

// MARK: - Arrivée

/// Livraison pas encore arrivée : explication et action principale « Marquer comme arrivée ».
private struct HostArrivalCard: View {
    let station: HostPickupViewModel.Station
    let isPending: Bool
    let markArrived: () -> Void
    @State private var isConfirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("La livraison n'est pas encore arrivée")
                    .font(.headline)
                    .foregroundStyle(.texte)
            } icon: {
                Image(systemName: "box.truck.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
            }
            Text("Dès que tu as reçu les produits, marque la livraison comme arrivée : les familles voient « Arrivée ! Viens la chercher » dans leur app et peuvent venir. Le scan et « Récupéré » s'activent à ce moment-là.")
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .fixedSize(horizontal: false, vertical: true)
            Button { isConfirming = true } label: {
                HStack(spacing: 8) {
                    if isPending { ProgressView() } else { Image(systemName: "shippingbox.and.arrow.backward.fill") }
                    Text("Marquer comme arrivée")
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(.grenier)
            .disabled(isPending || !station.canMarkArrived)
            .confirmationDialog("La livraison est arrivée ?", isPresented: $isConfirming, titleVisibility: .visible) {
                Button("Oui, marquer comme arrivée") { markArrived() }
                Button("Pas encore", role: .cancel) {}
            } message: {
                Text("\(familiesText) seront prévenues qu'elles peuvent venir chercher \(station.productName). Ce n'est pas réversible.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard(padding: 16)
    }

    private var familiesText: String {
        let count = station.shares.count
        return count == 1 ? String(localized: "La famille") : String(localized: "Les \(count) familles")
    }
}

/// Confirmation juste après « Marquer comme arrivée ».
private struct HostArrivalNotice: View {
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.economie)
                .symbolEffect(.bounce, value: reduceMotion ? false : true)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Arrivée enregistrée").font(.headline).foregroundStyle(.texte)
                Text("Les familles voient « Arrivée ! Viens la chercher » et sont prévenues par une notification. Tu peux commencer la remise.")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: dismiss) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .foregroundStyle(.texteSecondaire)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Fermer")
        }
        .padding(14)
        .background(Color.economie.opacity(0.12), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Progression

/// Familles servies et parts remises, avec leur barre.
private struct HostProgressTiles: View {
    let board: HostPickupViewModel.Board

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { families; shares }
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 12) { families; shares }
        }
    }

    private var families: some View {
        GrenierStatTile(String(localized: "\(board.familiesServed) sur \(board.familiesTotal)"),
                        systemImage: board.isComplete ? "person.2.circle.fill" : "person.2.fill",
                        tint: board.isComplete ? .economie : .grenier, style: .card, icon: .title,
                        title: Text("Familles servies"), numericValue: Double(board.familiesServed),
                        progress: board.familiesProgress,
                        accessibilityLabel: Text("\(board.familiesServed) familles servies sur \(board.familiesTotal)"))
    }

    private var shares: some View {
        GrenierStatTile(String(localized: "\(board.sharesHanded) sur \(board.sharesTotal)"),
                        systemImage: "shippingbox.fill",
                        tint: board.isComplete ? .economie : .grenier, style: .card, icon: .title,
                        title: Text("Parts remises"), numericValue: Double(board.sharesHanded),
                        progress: board.sharesProgress,
                        accessibilityLabel: Text("\(board.sharesHanded) parts remises sur \(board.sharesTotal)"))
    }
}

// MARK: - Listes

/// « À servir » puis « Servis », l'état vide et « Tout est remis ! ».
private struct HostBoardSections: View {
    let viewModel: HostPickupViewModel
    let station: HostPickupViewModel.Station
    let board: HostPickupViewModel.Board

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if board.isEmpty {
                HostEmptyCard(title: "Personne n'a réservé ce créneau", systemImage: "calendar.badge.exclamationmark",
                              message: "Choisis « Tous les créneaux » pour voir toutes les familles.")
            } else if station.isArrived && board.isComplete {
                HostAllDoneCard(board: board)
            }
            if !board.toServe.isEmpty || (!board.isEmpty && !board.isComplete) {
                VStack(alignment: .leading, spacing: 10) {
                    GrenierSectionHeader(String(localized: "À servir (\(board.familiesTotal - board.familiesServed))"),
                                         systemImage: "person.badge.clock.fill", font: .headline)
                    if board.toServe.isEmpty {
                        HostEmptyCard(title: "Aucune famille trouvée", systemImage: "magnifyingglass",
                                      message: "Vérifie l'orthographe du nom.")
                    } else {
                        rows(board.toServe)
                    }
                }
            }
            if !board.served.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    GrenierSectionHeader(String(localized: "Servis (\(board.familiesServed))"),
                                         systemImage: "checkmark.circle.fill", tint: .economie, font: .headline)
                    rows(board.served)
                }
            }
        }
        .animation(.snappy, value: board)
    }

    private func rows(_ rows: [HostPickupViewModel.Board.Row]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(Color.piste) }
                HostFamilyRow(row: row, unit: station.unit, canHandOut: station.isArrived,
                              isPending: viewModel.pendingHouseholdId == row.householdId) {
                    Task { await viewModel.markPickedUp(householdId: row.householdId, in: station.id) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard(padding: 16)
    }
}

/// Une famille : nom, parts × format, paiement, créneau ou remise, et « Récupéré ».
private struct HostFamilyRow: View {
    let row: HostPickupViewModel.Board.Row
    let unit: String?
    let canHandOut: Bool
    let isPending: Bool
    let markPickedUp: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { identity; Spacer(minLength: 8); action }
            VStack(alignment: .leading, spacing: 8) { identity; action }
        }
        .padding(.vertical, 10)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(.texte)
                .strikethrough(row.isPickedUp, color: .texteSecondaire)
            Text(quantityText)
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .monospacedDigit()
            HStack(spacing: 8) {
                paidBadge
                if let detail = detailText {
                    Label(detail, systemImage: row.isPickedUp ? "clock.badge.checkmark.fill" : "clock")
                        .font(.caption)
                        .foregroundStyle(.texteSecondaire)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var quantityText: String {
        let shares = PickupDesk.sharesLabel(row.quantity)
        return unit.map { String(localized: "\(shares) × \($0)") } ?? shares
    }

    /// Servi : « Servi à 14 h 05 · Amina » ; à servir : le créneau réservé.
    private var detailText: String? {
        if row.isPickedUp {
            let time = row.pickedUpAt.map { PickupPointFormatting.timeText($0) }
            switch (time, row.pickedUpByName) {
            case let (time?, name?): return String(localized: "Servi à \(time) · \(name)")
            case let (time?, nil): return String(localized: "Servi à \(time)")
            case let (nil, name?): return String(localized: "Servi · \(name)")
            case (nil, nil): return nil
            }
        }
        return row.slotStart.map { PickupPointFormatting.timeText($0) }
    }

    private var paidBadge: some View {
        Label(row.isPaid ? String(localized: "Payé") : String(localized: "Non payé"),
              systemImage: row.isPaid ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
            .font(.caption.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(row.isPaid ? Color.economie : Color.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((row.isPaid ? Color.economie : Color.orange).opacity(0.12), in: .capsule)
    }

    @ViewBuilder private var action: some View {
        if row.isPickedUp {
            Label("Récupéré", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.bounce, value: reduceMotion ? false : row.isPickedUp)
                .foregroundStyle(Color.economie)
                .frame(minHeight: 44)
                .accessibilityLabel("\(row.name), part récupérée")
        } else {
            Button(action: markPickedUp) {
                HStack(spacing: 6) {
                    if isPending { ProgressView() } else { Image(systemName: "hand.tap.fill") }
                    Text("Récupéré")
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .padding(.horizontal, 6)
            }
            .buttonStyle(.glass)
            .tint(.grenier)
            .disabled(isPending || !canHandOut)
            .accessibilityLabel("Marquer la part de \(row.name) comme récupérée")
            .accessibilityHint(canHandOut ? "" : String(localized: "Disponible quand la livraison est marquée comme arrivée"))
        }
    }
}

/// Toutes les familles sont passées.
private struct HostAllDoneCard: View {
    let board: HostPickupViewModel.Board

    var body: some View {
        VStack(spacing: 12) {
            GrenierSymbolScene(symbol: "checkmark.seal.fill", tint: .economie,
                               satellites: [.init("party.popper.fill", tint: .economie), .init("basket.fill"),
                                            .init("heart.fill", tint: .solidarite)],
                               trigger: board.familiesServed, isCompact: true)
            Text("Tout est remis !")
                .font(.title3.bold())
                .foregroundStyle(.texte)
            Text("\(board.familiesTotal) familles servies, \(board.sharesTotal) parts remises. Merci d'accueillir ton quartier !")
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .grenierCard(padding: 20)
        .accessibilityElement(children: .combine)
    }
}

private struct HostEmptyCard: View {
    let title: LocalizedStringKey
    let systemImage: String
    let message: LocalizedStringKey

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity)
        .grenierCard(padding: 12)
    }
}

// MARK: - Formatage

private enum HostFormat {
    /// « Samedi 28 novembre · 10 h – 13 h »
    static func slot(_ slot: PickupSlot) -> String {
        let locale = AppLanguage.formattingLocale
        let day = slot.start.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
        let start = PickupPointFormatting.timeText(slot.start)
        let end = PickupPointFormatting.timeText(slot.end)
        return "\(day.prefix(1).uppercased())\(day.dropFirst()) · \(start) – \(end)"
    }
}

// MARK: - Résultat

private struct HostOutcomeBanner: View {
    let outcome: HostPickupViewModel.Outcome
    let dismiss: () -> Void

    var body: some View {
        let isSuccess = outcome.result.isSuccess
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.bounce, value: outcome.id)
                .foregroundStyle(isSuccess ? Color.economie : Color.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(outcome.householdName.map { "\(outcome.result.title) · \($0)" } ?? outcome.result.title)
                    .font(.headline)
                Text(outcome.result.message).font(.subheadline).foregroundStyle(.texteSecondaire)
            }
            Spacer(minLength: 0)
            Button(action: dismiss) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .foregroundStyle(.texteSecondaire)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Fermer")
        }
        .padding(14)
        .background((isSuccess ? Color.economie : Color.orange).opacity(0.12), in: .rect(cornerRadius: 18))
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Scanner

/// Repli sans caméra (simulateur, appareil non compatible, permission refusée) : le code se tape ou se colle.
/// Même chemin que le scan (`HostPickupViewModel.scan`) : le contenu attendu est celui du QR de la famille.
private struct HostManualCodeEntry: View {
    let viewModel: HostPickupViewModel
    @State private var code = ""
    /// Évite qu'un double appui (bouton puis clavier) valide deux fois le même code.
    @State private var isSubmitting = false
    @FocusState private var isFocused: Bool

    /// Longueur maximale acceptée : un code réel fait moins de 100 caractères.
    private static let maxLength = 200

    private var trimmed: String { code.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Caméra indisponible").font(.headline)
                        Text("Colle le code de la famille, ou touche « Récupéré » dans la liste.")
                            .font(.subheadline)
                            .foregroundStyle(.texteSecondaire)
                    }
                } icon: {
                    Image(systemName: "camera.badge.ellipsis")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.grenier)
                }
                Button("Ouvrir les Réglages", systemImage: "gearshape.fill") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            .listRowBackground(Color.surface)

            Section {
                TextField("Entrer le code", text: $code, prompt: Text("\(ShareAllocator.qrCodePrefix)…"), axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit(submit)
                    .onChange(of: code) { _, new in
                        if new.count > Self.maxLength { code = String(new.prefix(Self.maxLength)) }
                    }
                Button("Valider le code", systemImage: "checkmark.circle.fill", action: submit)
                    .disabled(trimmed.isEmpty || isSubmitting)
            } header: {
                Label("Entrer le code", systemImage: "number.square.fill")
            }
            .listRowBackground(Color.surface)

            if let outcome = viewModel.outcome {
                Section {
                    HostOutcomeBanner(outcome: outcome) { viewModel.dismissOutcome() }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .grenierBackground()
        .onAppear { isFocused = true }
    }

    private func submit() {
        guard !trimmed.isEmpty, !isSubmitting else { return }
        let value = trimmed
        isSubmitting = true
        Task {
            await viewModel.scan(value)
            if viewModel.outcome?.result.isSuccess == true { code = "" }
            isSubmitting = false
        }
    }
}

#Preview("Saisie manuelle du code") {
    HostManualCodeEntry(viewModel: HostPickupViewModel(
        repositories: .fake(behavior: .instant), userId: "user-demo", householdId: "household-demo", groupId: nil
    ))
}

private struct HostScannerSheet: View {
    let viewModel: HostPickupViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if QRScannerView.isAvailable {
                    QRScannerView { code in Task { await viewModel.scan(code) } }
                        .ignoresSafeArea(edges: .bottom)
                        .overlay(alignment: .bottom) { resultOverlay }
                } else {
                    HostManualCodeEntry(viewModel: viewModel)
                }
            }
            .navigationTitle("Scanner un code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Terminer") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder private var resultOverlay: some View {
        if let outcome = viewModel.outcome {
            HostOutcomeBanner(outcome: outcome) { viewModel.dismissOutcome() }
                .padding(16)
        }
    }
}

#Preview("Remise — démo (en route et arrivée)") {
    NavigationStack {
        HostPickupScreen(viewModel: HostPickupViewModel(
            repositories: .fake(behavior: .instant, data: .demo), userId: FakeData.ID.amina,
            householdId: FakeData.ID.aminaHousehold, groupId: FakeData.ID.saintMichel
        ))
    }
}

#Preview("Remise — sombre") {
    NavigationStack {
        HostPickupScreen(viewModel: HostPickupViewModel(
            repositories: .fake(behavior: .instant, data: .demo), userId: FakeData.ID.amina,
            householdId: FakeData.ID.aminaHousehold, groupId: FakeData.ID.saintMichel
        ))
    }
    .preferredColorScheme(.dark)
}
