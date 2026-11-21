import SwiftUI

/// Point d'entrée de l'interface : affiche la navigation du portail actif.
struct RootView: View {
    @AppStorage(Portal.storageKey) private var portal: Portal = .family

    var body: some View {
        Group {
            switch portal {
            case .family: FamilyTabView()
            case .vendor: VendorTabView()
            }
        }
        .animation(.smooth, value: portal)
    }
}

#Preview("Clair") {
    RootView()
}

#Preview("Sombre") {
    RootView()
        .preferredColorScheme(.dark)
}
