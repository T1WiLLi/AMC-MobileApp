import SwiftUI

/// Profil commun aux deux portails, avec la bascule de portail (RQ-006).
struct ProfileScreen: View {
    @AppStorage(Portal.storageKey) private var portal: Portal = .family

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Portail actif", selection: $portal) {
                        ForEach(Portal.allCases) { portal in
                            Label(portal.title, systemImage: portal.systemImage)
                                .tag(portal)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Portail")
                } footer: {
                    Text("Un même compte peut acheter en famille et vendre comme producteur.")
                }

                Section("Compte") {
                    Label("Connexion et profil arrivent avec l'épic E02", systemImage: "person.crop.circle.badge.clock")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profil")
            .sensoryFeedback(.selection, trigger: portal)
        }
    }
}

#Preview("Clair") {
    ProfileScreen()
}

#Preview("Sombre") {
    ProfileScreen()
        .preferredColorScheme(.dark)
}
