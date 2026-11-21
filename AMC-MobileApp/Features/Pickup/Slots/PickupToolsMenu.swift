import SwiftUI

/// Point d'entrée de T-077 dans la Cueillette (F5) : un menu de la barre d'outils qui pousse
/// « Mon créneau » (RQ-064), « Point du groupe » (RQ-063, coordonnateur) et « Devenir hôte » (RQ-062).
/// À poser sur le contenu d'un `NavigationStack` : `.pickupTools(groupOrderId:)`.
private struct PickupToolsModifier: ViewModifier {
    let groupOrderId: String?
    @Environment(\.appContext) private var context
    @State private var route: Route?

    enum Route: Hashable, Identifiable {
        case slots(String)
        case pointPicker(String)
        case hostSetup

        var id: Self { self }
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let groupOrderId {
                            Button("Mon créneau", systemImage: "calendar.badge.clock") { route = .slots(groupOrderId) }
                            Button("Point du groupe", systemImage: "mappin.and.ellipse") {
                                route = .pointPicker(groupOrderId)
                            }
                        }
                        Button("Devenir hôte", systemImage: "house.and.flag.fill") { route = .hostSetup }
                    } label: {
                        Label("Organiser la cueillette", systemImage: "calendar.badge.clock")
                    }
                }
            }
            .navigationDestination(item: $route) { route in
                switch route {
                case .slots(let orderId):
                    SlotBookingScreen(viewModel: SlotBookingViewModel(
                        repositories: context.repositories, householdId: context.householdId, groupOrderId: orderId
                    ))
                case .pointPicker(let orderId):
                    PickupPointPickerScreen(viewModel: PickupPointPickerViewModel(
                        repositories: context.repositories, userId: context.userId, groupOrderId: orderId
                    ))
                case .hostSetup:
                    HostSetupScreen(viewModel: HostSetupViewModel(
                        repositories: context.repositories, userId: context.userId
                    ))
                }
            }
    }
}

extension View {
    /// Menu « Organiser la cueillette » (créneau, point du groupe, devenir hôte).
    func pickupTools(groupOrderId: String?) -> some View {
        modifier(PickupToolsModifier(groupOrderId: groupOrderId))
    }
}
