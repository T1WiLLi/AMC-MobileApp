import SwiftUI

struct PickupScreen: View {
    var body: some View {
        PlaceholderScreen(
            title: "Cueillette",
            systemImage: "qrcode",
            message: "Ton code QR, le point de cueillette et ton créneau (maquette F5).",
            epic: "E08"
        )
    }
}

#Preview("Clair") {
    PickupScreen()
}

#Preview("Sombre") {
    PickupScreen()
        .preferredColorScheme(.dark)
}
