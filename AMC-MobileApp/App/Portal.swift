import Foundation

/// Les deux portails de Grenier. Un compte peut avoir les deux ; le portail actif choisit la navigation.
enum Portal: String, CaseIterable, Identifiable, Sendable {
    case family
    case vendor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .family: "Familles"
        case .vendor: "Vendeurs"
        }
    }

    var systemImage: String {
        switch self {
        case .family: "house.fill"
        case .vendor: "storefront.fill"
        }
    }

    /// Clé `@AppStorage` du portail actif.
    static let storageKey = "activePortal"
}
