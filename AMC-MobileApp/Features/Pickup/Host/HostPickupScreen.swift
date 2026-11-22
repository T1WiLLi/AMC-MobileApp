import SwiftUI

/// T-181 : l'hôte remet les parts. Liste des ménages à servir pour son point (par commande et par créneau),
/// « Récupéré » d'un tap (transaction, haptique et coche) ou scan du code QR de la famille.
/// Poussé depuis la Cueillette (`PickupToolsMenu`), visible seulement pour un hôte.
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
                         message: "Quand une commande sera fermée chez toi, les ménages à servir apparaîtront ici."),
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
            if viewModel.state.value != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsScanner = true } label: {
                        Label("Scanner un code", systemImage: "qrcode.viewfinder")
                    }
                }
            }
        }
        .sheet(isPresented: $showsScanner) { HostScannerSheet(viewModel: viewModel) }
        .grenierHaptic(.success, trigger: viewModel.successes)
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

// MARK: - Contenu

private struct HostPickupContent: View {
    @Bindable var viewModel: HostPickupViewModel
    @Binding var showsScanner: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let content = viewModel.state.value, content.stations.count > 1 {
                    orderPicker(content.stations)
                }
                if let station = viewModel.selectedStation, let checklist = viewModel.checklist {
                    HostProgressCard(station: station, checklist: checklist)
                    if let outcome = viewModel.outcome {
                        HostOutcomeBanner(outcome: outcome) { viewModel.dismissOutcome() }
                    }
                    scanButton
                    if station.slots.count > 1 { slotFilter(station) }
                    HostChecklistCard(viewModel: viewModel, station: station, checklist: checklist)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .animation(.snappy, value: viewModel.outcome)
        }
    }

    private func orderPicker(_ stations: [HostPickupViewModel.Station]) -> some View {
        Picker("Commande", selection: Binding(
            get: { viewModel.selectedStation?.id ?? "" }, set: { viewModel.selectOrder($0) }
        )) {
            ForEach(stations) { station in Text(station.productName).tag(station.id) }
        }
        .pickerStyle(.menu)
        .grenierHaptic(.selection, trigger: viewModel.selectedOrderId)
    }

    private var scanButton: some View {
        Button { showsScanner = true } label: {
            Label("Scanner le code d'une famille", systemImage: "qrcode.viewfinder")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func slotFilter(_ station: HostPickupViewModel.Station) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: String(localized: "Tous les créneaux"), isOn: viewModel.selectedSlot == nil) {
                    viewModel.selectedSlot = nil
                }
                ForEach(station.slots, id: \.self) { slot in
                    chip(title: slot.formatted(date: .abbreviated, time: .shortened), isOn: viewModel.selectedSlot == slot) {
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

// MARK: - Progression

private struct HostProgressCard: View {
    let station: HostPickupViewModel.Station
    let checklist: PickupDesk.Checklist

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(station.productName, systemImage: "shippingbox.fill")
                .font(.title3.bold())
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.texte)
            Label(station.pointName, systemImage: "mappin.and.ellipse")
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
            ProgressView(value: checklist.progress)
                .tint(checklist.isComplete ? Color.economie : Color.grenier)
                .animation(.snappy, value: checklist.progress)
            Label {
                Text(checklist.summary).contentTransition(.numericText())
            } icon: {
                Image(systemName: checklist.isComplete ? "checkmark.seal.fill" : "person.2.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            .font(.subheadline.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(checklist.isComplete ? Color.economie : Color.texte)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard(padding: 16)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Liste

private struct HostChecklistCard: View {
    let viewModel: HostPickupViewModel
    let station: HostPickupViewModel.Station
    let checklist: PickupDesk.Checklist

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Ménages à servir", systemImage: "checklist")
                .font(.headline)
                .symbolRenderingMode(.hierarchical)
                .padding(.bottom, 6)
            if checklist.entries.isEmpty {
                Text("Personne n'a réservé ce créneau.")
                    .foregroundStyle(.texteSecondaire)
                    .padding(.vertical, 12)
            }
            ForEach(Array(checklist.entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Divider().overlay(Color.piste) }
                HostEntryRow(entry: entry, isPending: viewModel.pendingHouseholdId == entry.householdId) {
                    Task { await viewModel.markPickedUp(householdId: entry.householdId, in: station.id) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard(padding: 16)
        .animation(.snappy, value: checklist.entries)
    }
}

private struct HostEntryRow: View {
    let entry: PickupDesk.Checklist.Entry
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
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.displayName).font(.body.weight(.semibold)).foregroundStyle(.texte)
            Text(PickupDesk.sharesLabel(entry.quantity)).font(.subheadline).foregroundStyle(.texteSecondaire)
        }
    }

    @ViewBuilder private var action: some View {
        if entry.isPickedUp {
            Label("Récupéré", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.bounce, value: reduceMotion ? false : entry.isPickedUp)
                .foregroundStyle(Color.economie)
                .frame(minHeight: 44)
                .accessibilityLabel("\(entry.displayName), part récupérée")
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
            .buttonStyle(.borderedProminent)
            .disabled(isPending)
            .accessibilityLabel("Marquer la part de \(entry.displayName) comme récupérée")
        }
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
    @FocusState private var isFocused: Bool

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
                TextField("Entrer le code", text: $code, prompt: Text("GRENIER:…"), axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit(submit)
                Button("Valider le code", systemImage: "checkmark.circle.fill", action: submit)
                    .disabled(trimmed.isEmpty)
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
        guard !trimmed.isEmpty else { return }
        let value = trimmed
        Task {
            await viewModel.scan(value)
            if viewModel.outcome?.result.isSuccess == true { code = "" }
        }
    }
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
