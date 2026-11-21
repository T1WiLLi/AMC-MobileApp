import SwiftUI

/// Image de profil, de groupe ou bannière (T-122) : `grenier-media` (Firestore), `grenier-asset` (démo),
/// http(s) ou fichier. Remplit son cadre (« aspect fill ») et apparaît en fondu ; le `placeholder`
/// reste visible tant qu'il n'y a pas d'image (pas d'URL, chargement, erreur).
/// Le cache mémoire (`MediaImageLoader`) évite de relire Firestore quand une liste réaffiche l'image.
struct MediaImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder

    @Environment(\.appContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?

    init(url: URL?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder
        _image = State(initialValue: MediaImageLoader.shared.cachedImage(for: url))
    }

    var body: some View {
        Color.clear
            .overlay {
                ZStack {
                    placeholder()
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    }
                }
            }
            .clipped()
            .task(id: url) { await load() }
    }

    private func load() async {
        let loader = MediaImageLoader.shared
        guard let url else {
            image = nil
            return
        }
        if let cached = loader.cachedImage(for: url) {
            image = cached
            return
        }
        // Nouvelle URL (nouvelle version) : l'ancienne image reste affichée jusqu'à l'arrivée de la nouvelle.
        guard let loaded = try? await loader.image(for: url, store: context.repositories.images) else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { image = loaded }
    }
}

extension MediaImage where Placeholder == Color {
    init(url: URL?) {
        self.init(url: url) { Color.piste }
    }
}

#Preview("Assets de démo") {
    VStack(spacing: 16) {
        MediaImage(url: MediaURL.asset("BannerSaintMichel"))
            .frame(height: 140)
            .clipShape(.rect(cornerRadius: 24))
        MediaImage(url: MediaURL.asset("GroupPhotoSaintMichel"))
            .frame(width: 96, height: 96)
            .clipShape(.circle)
        MediaImage(url: nil) { Color.grenier.opacity(0.2) }
            .frame(width: 96, height: 96)
            .clipShape(.circle)
    }
    .padding()
    .grenierBackground()
    .environment(\.appContext, .instant)
}
