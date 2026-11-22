// CreateGroupSheet.swift
// B-059 : formulaire « Créer un groupe ». Nom, quartier, centre posé en touchant la carte, rayon de 1 à 2 km,
// public ou privé. La personne qui crée le groupe en est la coordonnatrice et son ménage le premier membre.
// T-188 (retour samuel) : même style que le reste de l'app : aperçu en direct, cartes Grenier sur fond crème,
// choix public / privé en cartes, une seule action principale en bas.

import MapKit
import SwiftUI

struct CreateGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: CreateGroupViewModel
    @State private var camera: MapCameraPosition = .automatic
    @FocusState private var focusedField: Field?
    let onCreated: (NeighborhoodGroup) -> Void

    private enum Field: Hashable { case name, neighborhood }

    init(repositories: AppRepositories, userId: String, householdId: String,
         onCreated: @escaping (NeighborhoodGroup) -> Void) {
        _model = State(initialValue: CreateGroupViewModel(repositories: repositories, userId: userId, householdId: householdId))
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    previewCard
                    if !model.hasRoomForAnotherGroup { limitCard }
                    identityCard
                    zoneCard
                    visibilityCard
                    coordinatorNote
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .grenierBackground()
            .safeAreaInset(edge: .bottom, spacing: 0) { createBar }
            .navigationTitle("Créer un groupe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
            }
            .onChange(of: model.draft) { model.formChanged() }
            .sensoryFeedback(.error, trigger: model.submitError) { _, new in new != nil }
            .sensoryFeedback(.success, trigger: model.createdGroup) { _, new in new != nil }
            .sensoryFeedback(.selection, trigger: model.isPublic)
            .onChange(of: model.createdGroup) { _, group in
                guard let group else { return }
                onCreated(group)
                dismiss()
            }
            .task {
                await model.load()
                camera = .region(region(around: model.center))
                // À la limite de groupes, pas de clavier : la carte d'avertissement passe d'abord.
                if model.name.isEmpty, model.hasRoomForAnotherGroup { focusedField = .name }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Aperçu

    /// Le groupe tel que les voisins le verront dans la liste, mis à jour à chaque frappe.
    private var previewCard: some View {
        HStack(alignment: .top, spacing: 14) {
            // Aux tailles d'accessibilité, le texte prend toute la largeur : pas de pastille.
            if !dynamicTypeSize.isAccessibilitySize {
                GrenierIconTile(systemImage: GrenierSymbol.groups, side: 52, font: .system(size: 22, weight: .semibold))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Aperçu")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.texteSecondaire)
                Text(previewName)
                    .font(.headline)
                    .foregroundStyle(model.trimmedNameCount == 0 ? Color.texteSecondaire : Color.texte)
                    .fixedSize(horizontal: false, vertical: true)
                Label(previewDetail, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(Color.texteSecondaire)
                    .symbolRenderingMode(.hierarchical)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.numericText())
                visibilityBadge
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .grenierCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aperçu du groupe : \(previewName), \(previewDetail), \(visibilityTitle(isPublic: model.isPublic))")
    }

    private var previewName: String {
        let name = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? String(localized: "Ton groupe de quartier") : name
    }

    private var previewDetail: String {
        let neighborhood = model.neighborhood.trimmingCharacters(in: .whitespacesAndNewlines)
        let radius = String(localized: "rayon de \(model.radiusText)")
        return neighborhood.isEmpty ? radius : "\(neighborhood) · \(radius)"
    }

    private var visibilityBadge: some View {
        Label(visibilityTitle(isPublic: model.isPublic), systemImage: visibilitySymbol(isPublic: model.isPublic))
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.grenier)
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(Color.grenier.opacity(0.12), in: .capsule)
            .contentTransition(.symbolEffect(.replace))
    }

    private var limitCard: some View {
        Label {
            Text("Ton ménage fait déjà partie de \(GroupRules.maxGroupsPerHousehold) groupes. Quittes-en un pour en créer un nouveau.")
                .font(.subheadline)
                .foregroundStyle(Color.texte)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
    }

    // MARK: Nom et quartier

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Nom et quartier", systemImage: "character.cursor.ibeam")
            field(systemImage: GrenierSymbol.groups, isFocused: focusedField == .name) {
                TextField("Voisins de la rue Jarry", text: $model.name, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($focusedField, equals: .name)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .neighborhood }
                    // Champ sur plusieurs lignes (grand texte) : Retour passe au champ suivant, sans saut de ligne.
                    .onChange(of: model.name) { _, value in
                        guard value.contains("\n") else { return }
                        model.name = value.replacingOccurrences(of: "\n", with: "")
                        focusedField = .neighborhood
                    }
                    .accessibilityLabel("Nom du groupe")
            }
            field(systemImage: "mappin.and.ellipse", isFocused: focusedField == .neighborhood) {
                TextField("Quartier", text: $model.neighborhood, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($focusedField, equals: .neighborhood)
                    .textContentType(.sublocality)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .onChange(of: model.neighborhood) { _, value in
                        guard value.contains("\n") else { return }
                        model.neighborhood = value.replacingOccurrences(of: "\n", with: "")
                        focusedField = nil
                    }
                    .accessibilityLabel("Quartier")
            }
            let isTooLong = model.trimmedNameCount > GroupRules.nameLengthRange.upperBound
            let footerLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
            footerLayout {
                Text("Les voisins le verront dans la liste des groupes.")
                    .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Text("\(model.trimmedNameCount)/\(GroupRules.nameLengthRange.upperBound)")
                    .monospacedDigit()
                    .foregroundStyle(isTooLong ? Color.red : Color.texteSecondaire)
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(model.trimmedNameCount) caractères sur \(GroupRules.nameLengthRange.upperBound)")
            }
            .font(.footnote)
            .foregroundStyle(Color.texteSecondaire)
        }
        .grenierCard()
    }

    /// Champ sur fond crème avec son icône, cerclé de Grenier quand il a le focus.
    private func field<Content: View>(systemImage: String, isFocused: Bool,
                                      @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            // Aux tailles d'accessibilité, le texte du champ garde toute la largeur.
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isFocused ? Color.grenier : Color.texteSecondaire)
                    .frame(minWidth: 28)
                    .accessibilityHidden(true)
            }
            content()
                .font(.body)
                .foregroundStyle(Color.texte)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 50)
        .background(Color.fond, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isFocused ? Color.grenier : Color.piste, lineWidth: isFocused ? 1.5 : 1)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isFocused)
    }

    // MARK: Zone

    private var zoneCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Zone du groupe", systemImage: "scope")
            centerMap
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 200 : 240)
                .clipShape(.rect(cornerRadius: 18))
                .overlay(alignment: .bottomLeading) {
                    if !dynamicTypeSize.isAccessibilitySize { mapHint }
                }
                .overlay(alignment: .topTrailing) { homeButton }
            if dynamicTypeSize.isAccessibilitySize {
                Text("Touche la carte pour placer le centre.")
                    .font(.footnote)
                    .foregroundStyle(Color.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            radiusControl
        }
        .grenierCard()
    }

    private var mapHint: some View {
        Label("Touche la carte pour placer le centre", systemImage: "hand.tap.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.texte)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .glassEffect(.regular, in: .capsule)
            .padding(10)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var homeButton: some View {
        if let home = model.homeCenter {
            Button("Recentrer sur chez moi", systemImage: "house.fill") {
                withGrenierAnimation(.snappy, reduceMotion: reduceMotion) {
                    model.center = home
                    camera = .region(region(around: home))
                }
            }
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            // Bouton flottant sur la carte : borné pour ne pas la masquer au très grand texte.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .disabled(model.isCenteredAtHome)
            .padding(10)
        }
    }

    private var radiusControl: some View {
        let range = Double(GroupRules.radiusRangeMeters.lowerBound)...Double(GroupRules.radiusRangeMeters.upperBound)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Rayon")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.texte)
                Spacer(minLength: 8)
                Text(model.radiusText)
                    .priceStyle(.title2.bold())
                    .foregroundStyle(Color.grenier)
                    .contentTransition(.numericText(value: Double(model.radiusMeters)))
            }
            .accessibilityHidden(true)
            Slider(value: radiusBinding, in: range, step: Double(CreateGroupViewModel.radiusStep)) {
                Text("Rayon")
            } minimumValueLabel: {
                Text("1 km").font(.caption).foregroundStyle(Color.texteSecondaire)
            } maximumValueLabel: {
                Text("2 km").font(.caption).foregroundStyle(Color.texteSecondaire)
            }
            .tint(Color.grenier)
            .accessibilityValue(model.radiusText)
            .sensoryFeedback(.selection, trigger: model.radiusMeters)
            Text("Les familles dans ce cercle verront le groupe près de chez elles.")
                .font(.footnote)
                .foregroundStyle(Color.texteSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Visibilité

    private var visibilityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Qui peut le trouver ?", systemImage: "eye.fill")
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
            layout {
                visibilityOption(isPublic: true)
                visibilityOption(isPublic: false)
            }
        }
        .grenierCard()
    }

    private func visibilityOption(isPublic: Bool) -> some View {
        let isSelected = model.isPublic == isPublic
        return Button {
            withGrenierAnimation(.snappy, reduceMotion: reduceMotion) { model.isPublic = isPublic }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: visibilitySymbol(isPublic: isPublic))
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isSelected ? Color.grenier : Color.texteSecondaire)
                        .symbolEffect(.bounce, value: reduceMotion ? false : isSelected)
                    Spacer(minLength: 4)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.grenier : Color.texteSecondaire.opacity(0.5))
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(visibilityTitle(isPublic: isPublic))
                    .font(.headline)
                    .foregroundStyle(Color.texte)
                Text(isPublic
                     ? String(localized: "Listé près de chez toi : tous les voisins peuvent le trouver et le rejoindre.")
                     : String(localized: "Jamais listé. On y entre seulement avec une invitation que tu envoies."))
                    .font(.footnote)
                    .foregroundStyle(Color.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(isSelected ? Color.grenier.opacity(0.08) : Color.fond, in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(isSelected ? Color.grenier : Color.piste, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func visibilityTitle(isPublic: Bool) -> String {
        isPublic ? String(localized: "Public") : String(localized: "Privé")
    }

    private func visibilitySymbol(isPublic: Bool) -> String {
        isPublic ? "globe.americas.fill" : "lock.fill"
    }

    private var coordinatorNote: some View {
        Label {
            Text("Tu seras la coordonnatrice ou le coordonnateur du groupe, et ton ménage son premier membre.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "star.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
        }
        .font(.footnote)
        .foregroundStyle(Color.texteSecondaire)
        .padding(.horizontal, 4)
    }

    // MARK: Barre du bas

    /// L'action principale de la feuille, avec ce qui manque juste au-dessus.
    private var createBar: some View {
        VStack(spacing: 8) {
            if let message = barMessage {
                Label(message, systemImage: model.submitError == nil ? "info.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(model.submitError == nil ? Color.texteSecondaire : Color.red)
                    .symbolRenderingMode(.hierarchical)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            Button {
                focusedField = nil
                Task { await model.create() }
            } label: {
                HStack(spacing: 8) {
                    if model.isSaving {
                        ProgressView().tint(Color.onAccent)
                    } else {
                        Image(systemName: "plus.circle.fill")
                    }
                    Text("Créer le groupe")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(.headline)
                // Le bouton reste sur une ligne : au-delà d'AX2, il cacherait le formulaire.
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .foregroundStyle(Color.onAccent)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(.grenier)
            .disabled(!model.canCreate)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        // Fondu crème derrière le bouton : le formulaire qui défile dessous ne brouille pas son libellé.
        .background {
            LinearGradient(stops: [.init(color: Color.fond.opacity(0), location: 0),
                                   .init(color: Color.fond.opacity(0.92), location: 0.35),
                                   .init(color: Color.fond, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .animation(reduceMotion ? nil : .smooth, value: barMessage)
    }

    /// Erreur du dépôt d'abord ; sinon ce qui manque, une fois qu'on a commencé à écrire.
    private var barMessage: String? {
        if let error = model.submitError { return error }
        if !model.name.isEmpty, let message = model.validationMessage { return message }
        return nil
    }

    // MARK: Carte

    private var centerMap: some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: [.pan, .zoom]) {
                // MapCircle ne se redessine pas quand son centre change : une identité par centre et rayon le recrée.
                ForEach([CircleKey(center: model.center, radiusMeters: model.radiusMeters)], id: \.self) { key in
                    MapCircle(center: key.center.clLocation, radius: CLLocationDistance(key.radiusMeters))
                        .foregroundStyle(Color.grenier.opacity(0.14))
                        .stroke(Color.grenier.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    Annotation(String(localized: "Centre du groupe"), coordinate: key.center.clLocation, anchor: .bottom) {
                        CenterPin()
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                withGrenierAnimation(.snappy, reduceMotion: reduceMotion) {
                    model.center = Geohash.Coordinate(coordinate)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Carte du centre du groupe")
        .accessibilityValue("Rayon de \(model.radiusText)")
        .accessibilityHint("Touche la carte pour déplacer le centre")
    }

    /// Cadre la carte sur le cercle, avec une marge.
    private func region(around center: Geohash.Coordinate) -> MKCoordinateRegion {
        let span = CLLocationDistance(GroupRules.radiusRangeMeters.upperBound) * 2.6
        return MKCoordinateRegion(center: center.clLocation, latitudinalMeters: span, longitudinalMeters: span)
    }

    private var radiusBinding: Binding<Double> {
        Binding(get: { Double(model.radiusMeters) },
                set: { model.radiusMeters = Int($0.rounded()) })
    }

    private func sectionHeader(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.texte)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// Épingle du centre : pastille Grenier au symbole du groupe, posée sur sa pointe.
private struct CenterPin: View {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 34

    var body: some View {
        let diameter = min(size, 48)
        VStack(spacing: 0) {
            Image(systemName: GrenierSymbol.groups)
                .font(.system(size: diameter * 0.4, weight: .semibold))
                .foregroundStyle(Color.onAccent)
                .frame(width: diameter, height: diameter)
                .background(Color.grenier, in: .circle)
                .padding(3)
                .background(Color.surface, in: .circle)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            Capsule()
                .fill(Color.grenier)
                .frame(width: 3, height: 8)
        }
    }
}

private struct CircleKey: Hashable {
    var center: Geohash.Coordinate
    var radiusMeters: Int
}

private extension Geohash.Coordinate {
    var clLocation: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

#if DEBUG
#Preview("Créer un groupe") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CreateGroupSheet(repositories: .fake(), userId: FakeData.ID.amina, householdId: FakeData.ID.aminaHousehold) { _ in }
    }
}

#Preview("Créer un groupe sombre") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CreateGroupSheet(repositories: .fake(), userId: FakeData.ID.amina, householdId: FakeData.ID.aminaHousehold) { _ in }
    }
    .preferredColorScheme(.dark)
}

#Preview("Créer un groupe AX5") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CreateGroupSheet(repositories: .fake(), userId: FakeData.ID.amina, householdId: FakeData.ID.aminaHousehold) { _ in }
    }
    .dynamicTypeSize(.accessibility5)
}
#endif
