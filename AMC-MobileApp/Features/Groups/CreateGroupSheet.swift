// CreateGroupSheet.swift
// B-059 : formulaire « Créer un groupe ». Nom, quartier, centre posé en touchant la carte, rayon de 1 à 2 km,
// public ou privé. La personne qui crée le groupe en est la coordonnatrice et son ménage le premier membre.

import MapKit
import SwiftUI

struct CreateGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            Form {
                if !model.hasRoomForAnotherGroup { limitSection }
                nameSection
                centerSection
                visibilitySection
            }
            .navigationTitle("Créer un groupe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isSaving {
                        ProgressView()
                    } else {
                        Button("Créer", systemImage: "checkmark") {
                            Task { await model.create() }
                        }
                        .disabled(!model.canCreate)
                    }
                }
            }
            .onChange(of: model.draft) { model.formChanged() }
            .sensoryFeedback(.error, trigger: model.submitError) { _, new in new != nil }
            .sensoryFeedback(.success, trigger: model.createdGroup) { _, new in new != nil }
            .onChange(of: model.createdGroup) { _, group in
                guard let group else { return }
                onCreated(group)
                dismiss()
            }
            .task {
                await model.load()
                camera = .region(region)
                if model.name.isEmpty { focusedField = .name }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Sections

    private var limitSection: some View {
        Section {
            Label("Ton ménage fait déjà partie de \(GroupRules.maxGroupsPerHousehold) groupes. Quittes-en un pour en créer un nouveau.",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.texte)
        }
    }

    private var nameSection: some View {
        Section {
            TextField("Voisins de la rue Jarry", text: $model.name)
                .focused($focusedField, equals: .name)
                .submitLabel(.next)
                .onSubmit { focusedField = .neighborhood }
            TextField("Quartier", text: $model.neighborhood)
                .focused($focusedField, equals: .neighborhood)
                .textContentType(.sublocality)
                .submitLabel(.done)
        } header: {
            Text("Nom et quartier")
        } footer: {
            Text("De \(GroupRules.nameLengthRange.lowerBound) à \(GroupRules.nameLengthRange.upperBound) caractères. Les voisins le verront dans la liste des groupes.")
        }
    }

    private var centerSection: some View {
        Section {
            centerMap
                .frame(height: 240)
                .listRowInsets(EdgeInsets())
            radiusSlider
        } header: {
            Text("Centre et rayon")
        } footer: {
            Text("Touche la carte pour placer le centre du groupe. Les familles dans ce cercle le verront près de chez elles.")
        }
    }

    private var radiusSlider: some View {
        let range = Double(GroupRules.radiusRangeMeters.lowerBound)...Double(GroupRules.radiusRangeMeters.upperBound)
        return VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Rayon", value: model.radiusText)
                .monospacedDigit()
            Slider(value: radiusBinding, in: range, step: Double(CreateGroupViewModel.radiusStep)) {
                Text("Rayon")
            } minimumValueLabel: {
                Text("1 km").font(.caption)
            } maximumValueLabel: {
                Text("2 km").font(.caption)
            }
            .tint(Color.grenier)
            .accessibilityValue(model.radiusText)
        }
    }

    private var visibilitySection: some View {
        Section {
            Toggle(isOn: privateBinding) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Groupe privé")
                        Text(visibilityDetail)
                            .font(.footnote)
                            .foregroundStyle(Color.texteSecondaire)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: model.isPublic ? "globe.americas.fill" : "lock.fill")
                        .foregroundStyle(Color.grenier)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .tint(Color.grenier)
        } footer: {
            visibilityFooter
        }
    }

    private var visibilityDetail: String {
        model.isPublic
            ? String(localized: "Listé près de chez toi : tous les voisins peuvent le trouver et le rejoindre.")
            : String(localized: "Jamais listé. On y entre seulement avec une invitation que tu envoies.")
    }

    @ViewBuilder
    private var visibilityFooter: some View {
        if let message = model.submitError {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if let message = model.validationMessage, !model.name.isEmpty {
            Text(message)
        } else {
            Text("Tu seras la coordonnatrice ou le coordonnateur du groupe, et ton ménage son premier membre.")
        }
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
                    Annotation(String(localized: "Centre du groupe"), coordinate: key.center.clLocation, anchor: .center) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.grenier)
                            .shadow(radius: 2, y: 1)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                withAnimation(reduceMotion ? nil : .snappy) {
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
    private var region: MKCoordinateRegion {
        MKCoordinateRegion(center: model.center.clLocation,
                           latitudinalMeters: CLLocationDistance(GroupRules.radiusRangeMeters.upperBound) * 2.6,
                           longitudinalMeters: CLLocationDistance(GroupRules.radiusRangeMeters.upperBound) * 2.6)
    }

    private var radiusBinding: Binding<Double> {
        Binding(get: { Double(model.radiusMeters) },
                set: { model.radiusMeters = Int($0.rounded()) })
    }

    private var privateBinding: Binding<Bool> {
        Binding(get: { !model.isPublic }, set: { model.isPublic = !$0 })
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
#endif
