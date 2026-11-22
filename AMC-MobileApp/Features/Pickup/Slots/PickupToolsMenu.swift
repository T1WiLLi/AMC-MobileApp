import SwiftUI

/// Point d'entrée de T-077 dans la Cueillette (F5) : un menu de la barre d'outils qui pousse
/// « Mon créneau » (RQ-064), « Point du groupe » (RQ-063, coordonnateur) et « Devenir hôte » (RQ-062).
/// À poser sur le contenu d'un `NavigationStack` : `.pickupTools(groupOrderId:)`.
private struct PickupToolsModifier: ViewModifier {
    let groupOrderId: String?
    @Environment(\.appContext) private var context
    @State private var route: Route?
    /// T-181 : l'utilisateur est hôte d'un point de cueillette ; le bouton « Remettre les parts » apparaît.
    @State private var isHost = false
    /// L'utilisateur coordonne un de ses groupes : il marque les livraisons arrivées et peut remettre les parts.
    @State private var isCoordinator = false

    private var handsOut: Bool { isHost || isCoordinator }

    enum Route: Hashable, Identifiable {
        case slots(String)
        case pointPicker(String)
        case hostSetup
        case hostPickup

        var id: Self { self }
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                if handsOut {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { route = .hostPickup } label: {
                            Label("Remettre les parts", systemImage: "qrcode.viewfinder")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let groupOrderId {
                            Button("Mon créneau", systemImage: "calendar.badge.clock") { route = .slots(groupOrderId) }
                            Button("Point du groupe", systemImage: "mappin.and.ellipse") {
                                route = .pointPicker(groupOrderId)
                            }
                        }
                        if handsOut {
                            Button("Remettre les parts", systemImage: "qrcode.viewfinder") { route = .hostPickup }
                        }
                        Button(isHost ? String(localized: "Mon point de cueillette") : String(localized: "Devenir hôte"), systemImage: "house.and.flag.fill") {
                            route = .hostSetup
                        }
                    } label: {
                        Label("Organiser la cueillette", systemImage: "calendar.badge.clock")
                    }
                }
            }
            .task(id: context.userId) {
                let points = (try? await context.repositories.pickupPoints.pickupPoints()) ?? []
                isHost = points.contains { $0.hostUserId == context.userId }
                let groups = (try? await context.repositories.groups.groups(ofHousehold: context.householdId)) ?? []
                isCoordinator = groups.contains { $0.coordinatorIds.contains(context.userId) }
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
                case .hostPickup:
                    HostPickupScreen(viewModel: HostPickupViewModel(
                        repositories: context.repositories, userId: context.userId,
                        householdId: context.householdId, groupId: context.groupId
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
