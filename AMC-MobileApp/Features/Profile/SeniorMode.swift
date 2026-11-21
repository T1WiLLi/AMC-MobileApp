// SeniorMode.swift
// RQ-019 : mode aîné. La préférence vit dans `AppUser.seniorMode` (synchronisée) et est recopiée ici
// dans `@AppStorage` pour que n'importe quelle vue l'applique sans recharger l'utilisateur.
// Usage : `.seniorModeTextSize()` sur un écran (ou à la racine de l'app pour tout agrandir).

import SwiftUI

enum SeniorMode {
    static let storageKey = "grenier.seniorMode"
    /// Texte très grand : jamais plus petit que AX1, jusqu'à AX5.
    static let textSizes: ClosedRange<DynamicTypeSize> = .accessibility1 ... .accessibility5
}

private struct SeniorModeTextSize: ViewModifier {
    @AppStorage(SeniorMode.storageKey) private var isOn = false

    func body(content: Content) -> some View {
        if isOn {
            content.dynamicTypeSize(SeniorMode.textSizes)
        } else {
            content
        }
    }
}

extension View {
    /// Agrandit le texte quand le mode aîné est actif.
    func seniorModeTextSize() -> some View {
        modifier(SeniorModeTextSize())
    }
}
