import SwiftUI

/// Carte d'accueil de la mascotte d'une visite (Noisette, FB-19 ; Racoonette), avant les bulles de la visite guidée (`GuidedTourOverlay`).
struct GuidedTourWelcomeCard: View {
    var tour: TourID = .noisette
    /// true : « C'est parti ! », false : « Plus tard ».
    let decide: (Bool) -> Void
    /// Hauteur du contenu (marges comprises), pour que la feuille épouse la carte au lieu d'une hauteur fixe.
    var onContentHeight: (CGFloat) -> Void = { _ in }

    @State private var accepted = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                TourMascotView(tour: tour, size: 132)
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    Text("Salut, moi c'est \(tour.mascotName) !")
                        .font(.title2.bold())
                        .fontDesign(.rounded)
                        .foregroundStyle(Color.texte)
                        .accessibilityAddTraits(.isHeader)
                    Text(tour.welcome)
                        .font(.body)
                        .foregroundStyle(Color.texteSecondaire)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 12) {
                    Button {
                        accepted = true
                        decide(true)
                    } label: {
                        Label("C'est parti !", systemImage: "sparkles")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.grenier)

                    Button {
                        decide(false)
                    } label: {
                        Label("Plus tard", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glass)
                    .tint(.grenier)
                }

                Label("Tu pourras revoir le tutoriel dans le Profil.", systemImage: "person.crop.circle")
                    .font(.footnote)
                    .foregroundStyle(Color.texteSecondaire)
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(24)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onContentHeight($0) }
        }
        .scrollBounceBehavior(.basedOnSize)
        .sensoryFeedback(.success, trigger: accepted)
    }
}

private struct GuidedTourWelcomeModifier: ViewModifier {
    let tourID: TourID
    let isReady: Bool

    private var tour: GuidedTour { GuidedTour.instance(for: tourID) }
    /// Choix fait sur la carte (ou feuille glissée vers le bas) : la feuille se ferme, et le choix n'est appliqué
    /// qu'une fois la feuille partie, pour que la première bulle ne se présente pas pendant qu'elle se retire.
    @State private var hasDecided = false
    @State private var accepted = false
    /// Hauteur de la carte : la moitié d'écran (`.medium`) coupait la dernière ligne en anglais et en grand texte.
    @State private var contentHeight: CGFloat?
    @State private var detent: PresentationDetent = .medium

    /// Hauteur ajustée au contenu ; au-delà, la feuille s'ouvre en grand et la carte défile.
    private var fittedDetent: PresentationDetent {
        contentHeight.map { .height($0) } ?? .medium
    }

    func body(content: Content) -> some View {
        content
            .sheet(
                isPresented: Binding(
                    get: { isReady && tour.showsWelcome && !hasDecided },
                    set: { isPresented in if !isPresented { hasDecided = true } }
                ),
                onDismiss: {
                    guard hasDecided else { return }
                    if accepted { tour.start() } else { tour.postpone() }
                }
            ) {
                GuidedTourWelcomeCard(tour: tourID) { decision in
                    accepted = decision
                    hasDecided = true
                } onContentHeight: { height in
                    let wasFitted = detent == fittedDetent
                    contentHeight = height.rounded(.up)
                    if wasFitted { detent = fittedDetent }
                }
                .presentationDetents([fittedDetent, .large], selection: $detent)
            }
            // « Revoir la visite guidée » : la carte peut revenir.
            .onChange(of: tour.showsWelcome) { _, showsWelcome in
                if showsWelcome {
                    hasDecided = false
                    accepted = false
                }
            }
    }
}

extension View {
    /// Montre la carte d'accueil de Noisette une fois l'écran prêt (`isReady`), si la visite n'a pas encore été vue.
    /// Glisser la feuille vers le bas vaut « Plus tard ».
    func guidedTourWelcome(_ tour: TourID = .noisette, isReady: Bool) -> some View {
        modifier(GuidedTourWelcomeModifier(tourID: tour, isReady: isReady))
    }
}

#Preview("Carte d'accueil") {
    Color.clear
        .grenierBackground()
        .sheet(isPresented: .constant(true)) {
            GuidedTourWelcomeCard { _ in }
                .presentationDetents([.medium, .large])
        }
}

#Preview("Racoonette") {
    GuidedTourWelcomeCard(tour: .racoonette) { _ in }
        .grenierBackground()
}

#Preview("Sombre") {
    GuidedTourWelcomeCard { _ in }
        .grenierBackground()
        .preferredColorScheme(.dark)
}
