import SwiftUI

struct PickupScreen: View {
    var body: some View {
        PlaceholderScreen(
            title: "Cueillette",
            systemImage: "qrcode",
            message: "Ton code QR, le point de cueillette et ton créneau."
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
