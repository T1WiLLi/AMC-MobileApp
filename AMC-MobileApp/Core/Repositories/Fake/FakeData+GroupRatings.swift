// FakeData+GroupRatings.swift
// Avis de démo des familles sur les groupes (T-174).
// Amina (Famille Benali) n'a pas encore noté Voisins de Saint-Michel (elle peut le faire) ; elle a déjà noté
// la Cuisine collective Villeray (elle peut modifier son avis). Hochelaga solidaire, où elle n'est pas membre,
// a ses propres avis : elle les lit sans pouvoir noter.

import Foundation

nonisolated extension FakeData {
    static let demoGroupRatings: [GroupRating] = {
        let now = Date.now
        let day: TimeInterval = 86_400
        func rating(_ groupId: String, _ householdId: String, _ author: String, _ stars: Int, _ comment: String?,
                    daysAgo: Double) -> GroupRating {
            let date = now.addingTimeInterval(-daysAgo * day)
            return GroupRating(id: householdId, groupId: groupId, householdId: householdId, authorName: author,
                               rating: stars, comment: comment, groupOrderId: nil, createdAt: date, updatedAt: date)
        }
        return [
            rating(ID.saintMichel, "household-voisin-1", "Julie T.", 5,
                   "Coordination au top, on sait toujours où et quand cueillir. Merci Amina !", daysAgo: 3),
            rating(ID.saintMichel, "household-voisin-2", "Minh N.", 5,
                   "Des voisins super gentils, et on économise vraiment sur l'épicerie.", daysAgo: 6),
            rating(ID.saintMichel, "household-voisin-3", "Fatou D.", 4,
                   "Bien organisé. Le créneau du samedi matin est parfois serré.", daysAgo: 9),
            rating(ID.saintMichel, "household-voisin-4", "Marc R.", 5, nil, daysAgo: 12),
            rating(ID.saintMichel, "household-voisin-5", "Rania H.", 4, nil, daysAgo: 15),
            rating(ID.hochelaga, "household-lopez", "Carlos L.", 5,
                   "Le groupe le plus solidaire du quartier : paniers suspendus chaque semaine.", daysAgo: 4),
            rating(ID.hochelaga, "household-gagnon", "Sophie G.", 4,
                   "Bonne ambiance, mais j'aimerais plus de lots de légumes.", daysAgo: 18),
            rating(ID.hochelaga, "household-pierre", "Jean P.", 3, nil, daysAgo: 25),
            rating(ID.villerayKitchen, ID.aminaHousehold, "Amina B.", 5,
                   "On cuisine ensemble chaque mois, et les achats groupés suivent.", daysAgo: 7),
            rating(ID.villerayKitchen, "household-voisin-1", "Julie T.", 5, nil, daysAgo: 5),
        ]
    }()
}
